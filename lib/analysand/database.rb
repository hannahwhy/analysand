require 'analysand/errors'
require 'analysand/http'
require 'analysand/reading'
require 'analysand/response'
require 'analysand/viewing'
require 'analysand/writing'

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
  # Keys are automatically JSON-encoded, as required by CouchDB.
  #
  # If you're running into problems with large key sets generating very long
  # query strings, you can use POST mode (CouchDB 0.9+):
  #
  #     vdb.view('video/by_artist', :keys => many_keys, :post => true)
  #
  # If you're reading many records from a view, you may want to stream them
  # in:
  #
  #     vdb.view('video/all', :stream => true)
  #
  # View data and metadata may be accessed as follows:
  #
  #     resp = vdb.view('video/recent', :limit => 10)
  #     resp.total_rows   # => 16
  #     resp.offset       # => 0
  #     resp.rows         # => an Enumerable
  #
  # See ViewResponse and StreamingViewResponse for more details.
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
  # NOTE: CouchDB 1.5.0 and 1.6.1 expect an _unescaped_ destination document
  # ID.
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
  # There are two ways to retrieve a token:
  #
  # 1. Establishing a session.  You can use
  #    Analysand::Instance#establish_sesssion for this.
  # 2. CouchDB may also issue updated session cookies as part of a response.
  #    You can access such cookies using #session_cookie on the response
  #    object.
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
    include Errors
    include Http
    include Reading
    include Viewing
    include Writing

    def initialize(uri)
      init_http_client(uri)
    end

    def self.create!(uri, credentials = nil)
      new(uri).tap { |db| db.create!(credentials) }
    end

    def self.drop(uri, credentials = nil)
      new(uri).drop(credentials)
    end

    def ping(credentials = nil)
      Response.new _get('', credentials)
    end

    def status(credentials = nil)
      ping(credentials).body
    end

    def create(credentials = nil)
      Response.new _put('', credentials)
    end

    def create!(credentials = nil)
      create(credentials).tap do |resp|
        raise ex(DatabaseError, resp) unless resp.success?
      end
    end

    def drop(credentials = nil)
      Response.new _delete('', credentials)
    end

    def drop!(credentials = nil)
      drop(credentials).tap do |resp|
        raise ex(CannotDropDatabase, resp) unless resp.success?
      end
    end

    def json_headers
      { 'Content-Type' => 'application/json' }
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
