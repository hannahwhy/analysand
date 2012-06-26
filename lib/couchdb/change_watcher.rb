require 'celluloid/io'
require 'http/parser'
require 'net/http'
require 'rack/utils'
require 'uri'
require 'yajl'

module Couchdb
  ##
  # A Celluloid::IO actor that watches the changes feed  of a CouchDB
  # database.  When a change is received, it passes the change to a
  # #process method.
  #
  # ChangeWatchers monitor changes using continuous mode and set up a heartbeat
  # to fire approximately every 10 seconds.
  #
  # Example usage:
  #
  #     class Accumulator < Couchdb::ChangeWatcher
  #       attr_accessor :results
  #
  #       # database may be either a URL-as-string or a Couchdb::Database.
  #       If overriding the initializer, you MUST call super.
  #       def initialize(database)
  #         super(database)
  #
  #         self.results = []
  #       end
  #
  #       # Can be used to set query parameters.  query is a Hash.
  #       # The query hash has two default parameters:
  #       #
  #       # | Key       | Value      |
  #       # | feed      | continuous |
  #       # | heartbeat | 10000      |
  #       #
  #       # It is NOT RECOMMENDED that they be changed.
  #       def customize_query(query)
  #       end
  #
  #       # Can be used to add headers.  req is a Net::HTTP::Get instance.
  #       def customize_request(req)
  #       end
  #
  #       # change is a Hash containing keys id, seq, and changes.  See [0] for
  #       # more information.
  #       def process(change)
  #         results << change
  #       end
  #
  #     a = Accumulator.new('http://localhost:5984/mydb')
  #
  #     # or with supervision:
  #     a = Accumulator.supervise('http://localhost:5984/mydb')
  #
  # ChangeWatchers begin watching for changes as soon as they are
  # initialized.  To send a shutdown message:
  #
  #     a.stop
  #
  # The watcher will terminate on the next heartbeat.
  #
  # [0]: http://guide.couchdb.org/draft/notifications.html#continuous
  class ChangeWatcher
    include Celluloid::IO
    include Rack::Utils

    # Read at most this many bytes off the socket at a time.
    QUANTUM = 4096

    def self.inherited(klass)
      # Without this, a subclass of ChangeWatcher will have a
      # Celluloid::Mailbox, not a Celluloid::IO::Mailbox.  The latter mailbox
      # is necessary to properly integrate message handling with the reactor.
      #
      # For example, if a Celluloid::Mailbox is in use and the reactor is
      # active, termination messages will not be processed.
      #
      # See https://github.com/celluloid/celluloid-io/issues/22.
      klass.send(:include, Celluloid::IO)
    end

    def initialize(database)
      @db = database

      start!
    end

    def start
      return if @started

      prepare
      connect

      @started = true
      @running = true

      while @running
        @socket.wait_readable
        @http_parser << @socket.read_nonblock(QUANTUM)
      end

      # Once we're done, close things up.
      @started = false
      @socket.close
    end

    def stop
      @running = false
    end

    ##
    # Called by Celluloid::IO's actor shutdown code.
    def finalize
      @socket.close if @socket && !@socket.closed?
    end

    ##
    # By default, this does nothing.  Provide behavior in a subclass.
    def customize_query(query)
    end

    ##
    # By default, this does nothing.  Provide behavior in a subclass.
    def customize_request(req)
    end

    ##
    # By default, this does nothing.  Provide behavior in a subclass.
    def process(change)
    end

    ##
    # Http::Parser callback.
    #
    # @private
    def on_headers_complete(parser)
      status = @http_parser.status_code.to_i

      raise "Request failed: expected status 200, got #{status}" unless status == 200
    end

    ##
    # Http::Parser callback.
    #
    # @private
    def on_body(chunk)
      @json_parser << chunk
    end

    ##
    # @private
    def prepare
      @uri = @db.respond_to?(:uri) ? @db.uri : URI(@db)
      @http_parser = Http::Parser.new(self)
      @json_parser = Yajl::Parser.new
      @json_parser.on_parse_complete = lambda { |doc| process(doc) }
    end

    ##
    # @private
    def connect
      @socket = TCPSocket.new(@uri.host, @uri.port)
      @socket.wait_writable

      query = {
        'feed' => 'continuous',
        'heartbeat' => '10000'
      }

      customize_query(query)
      q = build_query(query)

      req = Net::HTTP::Get.new(@uri.to_s + "/_changes?#{q}")

      customize_request(req)

      # Make the request.
      data = [
        "GET #{req.path} HTTP/1.1"
      ]

      req.each_header { |k, v| data << "#{k}: #{v}" }

      @socket.write(data.join("\r\n"))
      @socket.write("\r\n\r\n")
    end
  end
end
