require 'couchdb/errors'
require 'couchdb/response'
require 'couchdb/view_response'
require 'net/http/persistent'
require 'rack/utils'

module Couchdb
  ##
  # A wrapper around a CouchDB database in a CouchDB instance.
  #
  # Databases MUST be identified by an absolute URI; instantiating this class
  # with a relative URI will raise an exception.
  #
  #
  # Common tasks
  # ============
  #
  # Creating a database
  # -------------------
  #
  #     vdb = Couchdb::Database.create!('http://localhost:5984/videos/',
  #       credentials)
  #
  #  If the database was successfully created, you'll get back a
  #  Couchdb::Database instance.  If database creation failed, a
  #  DatabaseError containing a CouchDB response will be raised.
  #
  #
  # Opening a database
  # ------------------
  #
  #     vdb = Couchdb::Database.new('http://localhost:5984/videos/')
  #
  # The database SHOULD exist before you open it.
  #
  #
  # Closing connections
  # -------------------
  #
  #     vdb.close
  #
  # Note that this only closes the connection used for the current thread.  If
  # the database object is being used from several threads, there will still
  # be other connections active.  To close all connections, you must call
  # #close from all threads that are using the database object.
  #
  # It is safe to call #close without additional synchronization.
  #
  # After close returns, you can re-open a connection by calling #get, #put,
  # etc.
  #
  #
  # Dropping a database
  # -------------------
  #
  #     Couchdb::Database.drop('http://localhost:5984/videos',
  #                                      credentials)
  #
  #     # => #<Response code=200 ...>
  #     # => #<Response code=401 ...>
  #     # => #<Response code=404 ...>
  #
  #
  # Creating a document
  # -------------------
  #
  #     doc = { ... }
  #     vdb.put(doc_id, doc, credentials)  # => #<Response code=201 ...>
  #                                        # => #<Response code=403 ...>
  #                                        # => #<Response code=409 ...>
  #
  # Any object that responds to #to_json with a JSON representation of itself
  # may be used as the document.
  #
  # Updating a document
  # -------------------
  #
  #     doc = { '_rev' => rev, ... }
  #     vdb.put(doc_id, doc, credentials) # => #<Response code=201 ...>
  #                                       # => #<Response code=401 ...>
  #                                       # => #<Response code=409 ...>
  #
  #
  # You can also use #put!, which will raise Couchdb::DocumentNotSaved if the
  # response code is non-success.
  #
  #     begin
  #       vdb.put!(doc_id, doc, credentials)
  #     rescue Couchdb::DocumentNotSaved => e
  #       puts "Unable to save #{doc_id}, reason: #{e.response.body}"
  #     end
  #
  # #put!, if it returns, returns the response.
  #
  #
  # Deleting a document
  # -------------------
  #
  #     vdb.delete(doc_id, rev, credentials) # => #<Response code=200 ...>
  #                                          # => #<Response code=401 ...>
  #                                          # => #<Response code=409 ...>
  #
  # You can also use #delete!, which will raise Couchdb::DocumentNotDeleted if
  # the response code is non-success.
  #
  #
  # Retrieving a document
  # ---------------------
  #
  #     vdb.get(doc_id, credentials)  # => #<Response code=200 ...>
  #                                   # => #<Response code=401 ...>
  #                                   # => #<Response code=404 ...>
  #
  # Note: CouchDB treats forward slashes (/) specially.  For document IDs, /
  # denotes a separator between document ID and the name of an attachment.
  # This library makes use of that to implement attachment storage and
  # retrieval (see below).
  #
  # If you are using forward slashes in document IDs, you MUST encode them
  # (i.e. replace / with %2F).
  #
  #
  # Reading a view
  # --------------
  #
  #     vdb.view('video/recent', :key => ['member1'])
  #     vdb.view('video/by_artist', :startkey => 'a', :endkey => 'b')
  #
  # Keys are automatically JSON-encoded.  The view method returns a
  # ViewResponse, which may be accessed like this:
  #
  #     resp = vdb.view('video/recent', :limit => 10)
  #     resp.total_rows   # => 16
  #     resp.offset       # => 0
  #     resp.rows         # => [ { 'id' => ... }, ... } ]
  #
  # See ViewResponse for more details.
  #
  # You can also use view!, which will raise Couchdb::CannotAccessView on a
  # non-success response.
  #
  #
  # Uploading an attachment
  # -----------------------
  #
  #     vdb.put_attachment('doc1/attachment', io, {}, credentials)
  #       # => #<Response>
  #
  # The second argument MUST be an IO-like object.  The third argument MAY
  # contain any of the following options:
  #
  # * :rev: When specified, this will be used as the rev of the document that
  #   will own the attachment.  When not specified, no rev will be passed in
  #   the request.  In order to add attachments to existing documents, then,
  #   you MUST pass this option.
  # * :content_type: The MIME type of the attachment.
  #
  #
  # Retrieving an attachment
  # ------------------------
  #
  #     vdb.get_attachment('doc1/attachment', credentials) do |resp|
  #       # resp is a Net::HTTPResponse
  #     end
  #
  # or, if you don't need that level of control when reading the response
  # body:
  #
  #     vdb.get_attachment('doc1/attachment', credentials)
  #       # => Net::HTTPResponse
  #
  # When a block is passed, #get_attachment does not read the response body,
  # leaving that up to the programmer.  When a block is _not_ passed,
  # #get_attachment reads the body in full.
  #
  #
  # Pinging a database
  # ------------------
  #
  # Useful for connection testing:
  #
  #     vdb.ping    # => #<Response code=200 ...>
  #
  #
  # Getting database status
  # -----------------------
  #
  #     vdb.status # => { "db_name" => "videos", ... }
  #
  # The returned hash is a parsed form of the JSON received from a GET on the
  # database.
  #
  #
  # Acceptable credentials
  # ======================
  #
  # Every method that interacts with CouchDB has an optional credentials
  # parameter.  Two forms of credential are recognized by this class.
  #
  # 1. HTTP Basic authentication: When credentials is a hash of the form
  #
  #       { :username => "...", :password => "... }
  #
  #    then it will be transformed into an Authorization header for HTTP Basic
  #    authentication.
  #
  # 2. Token authentication: When credentials is a string, it is interpreted
  #    as a cookie from CouchDB's Session API.  The string is used as the
  #    value of a Cookie header.
  #
  # To get a token, use a CouchDB::Instance (ahem) instance.
  #
  # Omitting the credentials argument, or providing a form of credentials not
  # listed here, will result in no credentials being passed in the request.
  #
  #
  # Thread safety
  # =============
  #
  # Database objects may be shared across multiple threads.  The HTTP client
  # used by this object (Net::HTTP::Persistent) creates one persistent
  # connection per (uri.host, uri.port, thread) tuple, so connection pooling
  # is also done.
  class Database
    include Rack::Utils

    JSON_VALUE_PARAMETERS = %w(key keys startkey endkey).map(&:to_sym)

    attr_reader :http
    attr_reader :uri

    def self.create!(uri, credentials = nil)
      new(uri).tap { |db| db.create!(credentials) }
    end

    def self.drop(uri, credentials = nil)
      new(uri).drop(credentials)
    end

    def initialize(uri)
      raise InvalidURIError, 'You must supply an absolute URI' unless uri.absolute?

      @http = Net::HTTP::Persistent.new('catalog_database')
      @uri = uri

      # URI.join (used to calculate a document URI) will replace the database
      # name unless we make it clear that the database is part of the path
      unless uri.path.end_with?('/')
        uri.path += '/'
      end
    end

    def ping(credentials = nil)
      req = Net::HTTP::Get.new(uri.to_s)
      set_credentials(req, credentials)

      Response.new(http.request(uri, req))
    end

    def status(credentials = nil)
      ping(credentials).body
    end

    def close
      http.shutdown
    end

    def put(doc_id, doc, credentials = nil, options = {})
      uri = doc_uri(doc_id)
      uri.query = build_query(options)
      req = Net::HTTP::Put.new(uri.to_s)

      set_credentials(req, credentials)
      req.body = doc.to_json

      Response.new(http.request(uri, req))
    end

    def put!(doc_id, doc, credentials = nil, options = {})
      put(doc_id, doc, credentials, options).tap do |resp|
        raise ex(DocumentNotSaved, resp) unless resp.success?
      end
    end

    def put_attachment(loc, io, credentials = nil, options = {})
      uri = doc_uri(loc)

      if options[:rev]
        uri.query = build_query('rev' => options[:rev])
      end

      req = Net::HTTP::Put.new(uri.to_s)
      req.body = io.read

      if options[:content_type]
        req.add_field('Content-Type', options[:content_type])
      end

      set_credentials(req, credentials)

      Response.new(http.request(uri, req))
    end

    def delete(doc_id, rev, credentials = nil)
      uri = doc_uri(doc_id)
      req = Net::HTTP::Delete.new(uri.to_s)

      set_credentials(req, credentials)
      req.add_field('If-Match', rev)

      Response.new(http.request(uri, req))
    end

    def delete!(doc_id, rev, credentials = nil)
      delete(doc_id, rev, credentials).tap do |resp|
        raise ex(DocumentNotDeleted, resp) unless resp.success?
      end
    end

    def get(doc_id, credentials = nil)
      uri = doc_uri(doc_id)
      req = Net::HTTP::Get.new(uri.to_s)

      set_credentials(req, credentials)

      Response.new(http.request(uri, req))
    end

    def head(doc_id, credentials = nil)
      uri = doc_uri(doc_id)
      req = Net::HTTP::Head.new(uri.to_s)

      set_credentials(req, credentials)

      Response.new(http.request(uri, req))
    end

    def get_attachment(loc, credentials = nil, &block)
      uri = doc_uri(loc)
      req = Net::HTTP::Get.new(uri.to_s)

      set_credentials(req, credentials)

      http.request(uri, req)
    end

    def view(view_name, parameters = {}, credentials = nil)
      design_doc, view_name = view_name.split('/', 2)
      uri = doc_uri("_design/#{design_doc}/_view/#{view_name}")

      JSON_VALUE_PARAMETERS.each do |p|
        if parameters.has_key?(p)
          parameters[p] = parameters[p].to_json
        end
      end

      uri.query = build_query(parameters)
      req = Net::HTTP::Get.new(uri.to_s)

      set_credentials(req, credentials)

      ViewResponse.new(http.request(uri, req))
    end

    def view!(view_name, parameters = {}, credentials = nil)
      view(view_name, parameters, credentials).tap do |resp|
        raise ex(CannotAccessView, resp) unless resp.success?
      end
    end

    ##
    # While you can use this, you shouldn't.  Use the class-level create
    # instead.
    #
    # @private
    def create!(credentials)
      req = Net::HTTP::Put.new(uri.to_s)
      set_credentials(req, credentials)

      Response.new(http.request(uri, req)).tap do |resp|
        if !resp.success?
          raise DatabaseError, "Database #{uri} could not be created (response code: #{resp.code})"
        end
      end
    end

    ##
    # While you can use this, you shouldn't.  Use the class-level drop
    # instead.
    #
    # @private
    def drop(credentials)
      req = Net::HTTP::Delete.new(uri.to_s)
      set_credentials(req, credentials)

      Response.new(http.request(uri, req))
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

    ##
    # @private
    def doc_uri(doc_id)
      URI(uri.to_s + URI.escape(doc_id))
    end

    ##
    # @private
    def ex(klass, response)
      klass.new("Expected response to have code 2xx, got #{response.code} instead").tap do |ex|
        ex.response = response
      end
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
