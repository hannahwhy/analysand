require 'celluloid/logger'

module Couchdb
  module ConnectionTesting
    include Celluloid::Logger

    ##
    # Issues a HEAD request to the given URI.  If it responds with a success or
    # redirection code, returns true; otherwise, returns false.
    def test_http_connection(uri)
      begin
        resp = Net::HTTP.start(uri.host, uri.port) { |h| h.head(uri.request_uri) }

        case resp
        when Net::HTTPSuccess then true
        when Net::HTTPRedirection then true
        else
          error "Expected HEAD #{uri} to return 200, got #{resp.code} (#{resp.body}) instead"
          false
        end
      rescue => e
        error "#{e.class} (#{e.message}) caught while attempting connection to #{uri}"
        error e.backtrace.join("\n")
        false
      end
    end

    ##
    # Periodically checks a URI for success using test_http_connection, and
    # raises an error if test_http_connection does not return success before
    # the timeout is reached.
    def wait_for_http_service(uri, timeout = 30)
      state = 1.upto(timeout) do
        if test_http_connection(Catalog::Settings.solr_uri)
          break :started
        else
          sleep 1
        end
      end

      unless state == :started
        raise "#{uri.to_s} took longer than #{timeout} seconds to return a success response"
      end
    end
  end
end
