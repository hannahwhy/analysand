require 'celluloid'
require 'celluloid/io'
require 'analysand/connection_testing'
require 'http/parser'
require 'net/http'
require 'rack/utils'
require 'uri'
require 'yajl'

module Analysand
  ##
  # A Celluloid::IO actor that watches the changes feed of a CouchDB database.
  # When a change is received, it passes the change to a #process method.
  #
  # ChangeWatchers monitor changes using continuous mode and set up a heartbeat
  # to fire approximately every 10 seconds.
  #
  # ChangeWatchers begin watching for changes as soon as they are initialized.
  # To send a shutdown message:
  #
  #     a.stop
  #
  # The watcher will terminate on the next heartbeat.
  #
  #
  # Failure modes
  # =============
  #
  # ChangeWatcher deals with the following failures in the following ways:
  #
  # * If Errno::ECONNREFUSED is raised whilst connecting to CouchDB, it will
  #   retry the connection in 30 seconds.
  # * If the connection to CouchDB's changes feed is abruptly terminated, it
  #   dies.
  # * If an exception is raised during HTTP or JSON parsing, it dies.
  #
  # Situations where the actor dies should be handled by a supervisor.
  #
  #
  # Example usage
  # =============
  #
  #     class Accumulator < Analysand::ChangeWatcher
  #       attr_accessor :results
  #
  #       def initialize(database)
  #         super(database)
  #
  #         self.results = []
  #       end
  #
  #       def process(change)
  #         results << change
  #
  #         # Once a ChangeWatcher has successfully processed a change, it
  #         # SHOULD invoke #change_processed.
  #         change_processed(change)
  #       end
  #     end
  #
  #     a = Accumulator.new('http://localhost:5984/mydb')
  #
  #     # or with supervision:
  #     a = Accumulator.supervise('http://localhost:5984/mydb')
  class ChangeWatcher
    include Celluloid::IO
    include Celluloid::Logger
    include ConnectionTesting
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

    ##
    # Checks services.  If all services pass muster, enters a read loop.
    #
    # The database parameter may be either a URL-as-string or a
    # Analysand::Database.
    #
    # If overriding the initializer, you MUST call super.
    def initialize(database)
      @db = database
      @waiting = {}
      @http_parser = Http::Parser.new(self)
      @json_parser = Yajl::Parser.new
      @json_parser.on_parse_complete = lambda { |doc| process(doc) }

      start!
    end

    # The URI of the changes feed.  This URI incorporates any changes
    # made by customize_query.
    def changes_feed_uri
      query = {
        'feed' => 'continuous',
        'heartbeat' => '10000'
      }

      customize_query(query)

      uri = (@db.respond_to?(:uri) ? @db.uri : URI(@db)).dup
      uri.path += '/_changes'
      uri.query = build_query(query)
      uri
    end

    # The connection_ok method is called before connecting to the changes feed.
    # By default, it checks that there's an HTTP service listening on the
    # changes feed.
    #
    # If the method returns true, then we connect to the changes feed and begin
    # processing.  If it returns false, a warning message is logged and the
    # connection check will be retried in 30 seconds.
    #
    # This method can be overridden if you need to check additional services.
    # When you override the method, make sure that you don't discard the return
    # value of the original definition:
    #
    #     # Wrong
    #     def connection_ok
    #       super
    #       ...
    #     end
    #
    #     # Right
    #     def connection_ok
    #       ok = super
    #
    #       ok && my_other_test
    #     end
    def connection_ok
      test_http_connection(changes_feed_uri)
    end

    def start
      return if @started

      @started = true

      while !connection_ok
        error "Some services used by #{self.class.name} did not check out ok; will retry in 30 seconds"
        sleep 30
      end

      connect

      info "#{self.class} entering read loop"

      @running = true

      while @running
        @http_parser << @socket.readpartial(QUANTUM)
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
    # Can be used to set query parameters.  query is a Hash.  The query hash
    # has two default parameters:
    #
    # | Key       | Value      |
    # | feed      | continuous |
    # | heartbeat | 10000      |
    #
    # It is NOT RECOMMENDED that they be changed.
    #
    # By default, this does nothing.  Provide behavior in a subclass.
    def customize_query(query)
    end

    ##
    # Can be used to add headers.  req is a Net::HTTP::Get instance.
    #
    # By default, this does nothing.  Provide behavior in a subclass.
    def customize_request(req)
    end

    ##
    # This method should implement your change-processing logic.
    #
    # change is a Hash containing keys id, seq, and changes.  See [0] for
    # more information.
    #
    # By default, this does nothing.  Provide behavior in a subclass.
    #
    # [0]: http://guide.couchdb.org/draft/notifications.html#continuous
    def process(change)
    end

    class Waiter < Celluloid::Future
      alias_method :wait, :value
    end

    ##
    # Returns an object that can be used to block a thread until a document
    # with the given ID has been processed.
    #
    # Intended for testing.
    def waiter_for(id)
      @waiting[id] = true

      Waiter.new do
        loop do
          break true if !@waiting[id]
          sleep 0.1
        end
      end
    end

    ##
    # Notify waiters.
    def change_processed(change)
      @waiting.delete(change['id'])
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
    def connect
      req = prepare_request
      uri = changes_feed_uri

      info "#{self.class} connecting to #{req.path}"

      @socket = TCPSocket.new(uri.host, uri.port)
      @socket.wait_writable

      # Make the request.
      data = [
        "GET #{req.path} HTTP/1.1"
      ]

      req.each_header { |k, v| data << "#{k}: #{v}" }

      @socket.write(data.join("\r\n"))
      @socket.write("\r\n\r\n")
    end

    ##
    # @private
    def prepare_request
      Net::HTTP::Get.new(changes_feed_uri.to_s).tap do |req|
        customize_request(req)
      end
    end
  end
end
