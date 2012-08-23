require 'analysand/bulk_response'
require 'analysand/errors'
require 'analysand/response'
require 'analysand/view_response'
require 'net/http/persistent'
require 'rack/utils'

module Analysand
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
  #     vdb = Analysand::Database.create!('http://localhost:5984/videos/',
  #       credentials)
  #
  #  If the database was successfully created, you'll get back a
  #  Analysand::Database instance.  If database creation failed, a
  #  DatabaseError containing a CouchDB response will be raised.
  #
  #  You can also instantiate a database and then create it:
  #
  #     vdb = Analysand::Database.new('http://localhost:5984/videos')
  #     vdb.create(credentials)  # => #<Response ...>
  #
  #
  # Dropping a database
  # -------------------
  #
  #     Analysand::Database.drop('http://localhost:5984/videos',
  #                                      credentials)
  #
  #     # => #<Response code=200 ...>
  #     # => #<Response code=401 ...>
  #     # => #<Response code=404 ...>
  #
  #  You can also instantiate a database and then drop it:
  #
  #     db = Analysand::Database.new('http://localhost:5984/videos')
  #     db.drop   # => #<Response ...>
  #
  #  You can also use #drop!, which will raise Analysand::CannotDropDatabase
  #  on a non-success response.
  #
  #
  # Opening a database
  # ------------------
  #
  #     vdb = Analysand::Database.new('http://localhost:5984/videos/')
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
  # You can also use #put!, which will raise Analysand::DocumentNotSaved if the
  # response code is non-success.
  #
  #     begin
  #       vdb.put!(doc_id, doc, credentials)
  #     rescue Analysand::DocumentNotSaved => e
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
  # You can also use #delete!, which will raise Analysand::DocumentNotDeleted if
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
  # You can also use #get!, which will raise Analysand::CannotAccessDocument if
  # the response code is non-success.
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
  # You can also use view!, which will raise Analysand::CannotAccessView on a
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
  # Copying a document
  # ------------------
  #
  #     vdb.copy('source', 'destination', credentials)
  #     # => #<Response code=201 ...>
  #     # => #<Response code=401 ...>
  #     # => #<Response code=409 ...>
  #
  # To overwrite, you'll need to provide a rev of the destination document:
  #
  #     vdb.copy('source', "destination?rev=#{rev}", credentials)
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
      query = options
      headers = { 'Content-Type' => 'application/json' }

      Response.new _put(doc_id, credentials, options, headers, doc.to_json)
    end

    def put!(doc_id, doc, credentials = nil, options = {})
      put(doc_id, doc, credentials, options).tap do |resp|
        raise ex(DocumentNotSaved, resp) unless resp.success?
      end
    end

    def bulk_docs(docs, credentials = nil, options = {})
      headers = { 'Content-Type' => 'application/json' }
      body = { 'docs' => docs }
      body['all_or_nothing'] = true if options[:all_or_nothing]

      BulkResponse.new _post('_bulk_docs', credentials, {}, headers, body.to_json)
    end

    def bulk_docs!(docs, credentials = nil, options = {})
      bulk_docs(docs, credentials, options).tap do |resp|
        raise ex(BulkOperationFailed, resp) unless resp.success?
      end
    end

    def copy(source, destination, credentials = nil)
      headers = { 'Destination' => destination }

      Response.new _copy(source, credentials, {}, headers, nil)
    end

    def put_attachment(loc, io, credentials = nil, options = {})
      query = {}
      headers = {}

      if options[:rev]
        query['rev'] = options[:rev]
      end

      if options[:content_type]
        headers['Content-Type'] = options[:content_type]
      end

      Response.new _put(loc, credentials, query, headers, io.read)
    end

    def delete(doc_id, rev, credentials = nil)
      headers = { 'If-Match' => rev }

      Response.new _delete(doc_id, credentials, {}, headers, nil)
    end

    def delete!(doc_id, rev, credentials = nil)
      delete(doc_id, rev, credentials).tap do |resp|
        raise ex(DocumentNotDeleted, resp) unless resp.success?
      end
    end

    def get(doc_id, credentials = nil)
      Response.new(_get(doc_id, credentials))
    end

    def get!(doc_id, credentials = nil)
      get(doc_id, credentials).tap do |resp|
        raise ex(CannotAccessDocument, resp) unless resp.success?
      end
    end

    def head(doc_id, credentials = nil)
      Response.new(_head(doc_id, credentials))
    end

    def get_attachment(loc, credentials = nil)
      _get(loc, credentials)
    end

    def view(view_name, parameters = {}, credentials = nil)
      design_doc, view_name = view_name.split('/', 2)
      view_path = "_design/#{design_doc}/_view/#{view_name}"

      JSON_VALUE_PARAMETERS.each do |p|
        if parameters.has_key?(p)
          parameters[p] = parameters[p].to_json
        end
      end

      ViewResponse.new _get(view_path, credentials, parameters, {})
    end

    def view!(view_name, parameters = {}, credentials = nil)
      view(view_name, parameters, credentials).tap do |resp|
        raise ex(CannotAccessView, resp) unless resp.success?
      end
    end

    def create(credentials = nil)
      req = Net::HTTP::Put.new(uri.to_s)
      set_credentials(req, credentials)

      Response.new(http.request(uri, req))
    end

    def create!(credentials = nil)
      create(credentials).tap do |resp|
        raise ex(DatabaseError, resp) unless resp.success?
      end
    end

    def drop(credentials = nil)
      req = Net::HTTP::Delete.new(uri.to_s)
      set_credentials(req, credentials)

      Response.new(http.request(uri, req))
    end

    def drop!(credentials = nil)
      drop(credentials).tap do |resp|
        raise ex(CannotDropDatabase, resp) unless resp.success?
      end
    end

    %w(Head Get Put Post Delete Copy).each do |m|
      str = <<-END
        def _#{m.downcase}(doc_id, credentials, query = {}, headers = {}, body = nil)
          _req(Net::HTTP::#{m}, doc_id, credentials, query, headers, body)
        end
      END

      class_eval str, __FILE__, __LINE__
    end

    ##
    # @private
    def _req(klass, doc_id, credentials, query, headers, body)
      uri = URI(self.uri.to_s + URI.escape(doc_id))
      uri.query = build_query(query) unless query.empty?

      req = klass.new(uri.request_uri)

      headers.each { |k, v| req.add_field(k, v) }
      req.body = body if body && req.request_body_permitted?
      set_credentials(req, credentials)

      http.request(uri, req)
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
    def ex(klass, response)
      klass.new("Expected response to have code 2xx, got #{response.code} instead").tap do |ex|
        ex.response = response
      end
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
