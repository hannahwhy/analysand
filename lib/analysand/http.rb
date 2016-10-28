require 'forwardable'
require 'net/http/persistent'
require 'rack/utils'
require 'uri'

module Analysand
  # Private: HTTP client methods for Database and Instance.
  #
  # Users of this module MUST set @http and @uri in their initializer.  @http
  # SHOULD be a Net::HTTP::Persistent instance, and @uri SHOULD be a URI
  # instance.
  module Http
    extend Forwardable

    include Rack::Utils

    attr_reader :http
    attr_reader :uri

    SSL_METHODS = %w(
      certificate ca_file cert_store private_key
      reuse_ssl_sessions ssl_version verify_callback verify_mode
    ).map { |m| [m, "#{m}="] }.flatten

    def_delegators :http, *SSL_METHODS

    def init_http_client(uri)
      unless uri.respond_to?(:path) && uri.respond_to?(:absolute?)
        uri = URI(uri)
      end

      raise InvalidURIError, 'You must supply an absolute URI' unless uri.absolute?

      @http = Net::HTTP::Persistent.new(name: 'analysand')
      @uri = uri

      # Document IDs and other database bits are appended to the URI path,
      # so we need to make sure that it ends in a /.
      unless uri.path.end_with?('/')
        uri.path += '/'
      end
    end

    def close
      http.shutdown
    end

    %w(Head Get Put Post Delete Copy).each do |m|
      str = <<-END
        def _#{m.downcase}(doc_id, credentials, query = {}, headers = {}, body = nil, block = nil)
          _req(Net::HTTP::#{m}, doc_id, credentials, query, headers, body, block)
        end
      END

      module_eval str, __FILE__, __LINE__
    end

    ##
    # @private
    def _req(klass, doc_id, credentials, query, headers, body, block)
      uri = self.uri.dup
      uri.path += doc_id
      uri.query = build_query(query) unless query.empty?

      req = klass.new(uri.request_uri)

      headers.each { |k, v| req.add_field(k, v) }
      req.body = body if body && req.request_body_permitted?
      set_credentials(req, credentials)

      http.request(uri, req, &block)
    end

    ##
    # Sets credentials on a request object.
    #
    # If creds is a hash containing :username and :password keys, HTTP basic
    # authorization is used.  If creds is a string, the string is added as a
    # cookie.
    def set_credentials(req, creds)
      return unless creds

      if String === creds
        req.add_field('Cookie', creds)
      elsif creds[:username] && creds[:password]
        req.basic_auth(creds[:username], creds[:password])
      end
    end
  end
end
