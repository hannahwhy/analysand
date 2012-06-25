require 'http/parser'
require 'socket'
require 'uri'
require 'yajl'

module Couchdb
  ##
  # This is a support class for Couchdb::Database#changes.  It's not meant to
  # be used outside that context.
  class ChangeWatcher
    # Read at most this many bytes off the socket at a time.
    QUANTUM = 4096

    def initialize(req)
      # The request.
      @req = req

      # Used to terminate the read loop.
      @tr, @tw = IO.pipe

      # The socket to CouchDB.
      uri = URI(@req.path)
      @socket = TCPSocket.new(uri.host, uri.port)
    end

    def stop
      @tw.write_nonblock(1)
    end

    ##
    # @private
    def start(credentials, &block)
      # Set up parsers.
      http_parser = Http::Parser.new
      json_parser = Yajl::Parser.new

      http_parser.on_headers_complete = proc do
        status = http_parser.status_code.to_i
        
        raise "Request failed: expected status 200, got #{status}" unless status == 200
      end

      http_parser.on_body = proc do |chunk|
        json_parser << chunk
      end

      json_parser.on_parse_complete = block

      # Make the request.
      _, wr, _ = select([], [@socket], [])

      raise "Select returned, but #{@socket} isn't ready to accept writes" unless wr.include?(@socket)

      data = [
        "GET #{@req.path} HTTP/1.1"
      ]

      @req.each_header { |k, v| data << "#{k}: #{v}" }

      data << ""
      data << ""

      @socket.write(data.join("\r\n"))

      # Parse chunks of data off the socket.
      loop do
        rd, _, _ = select([@socket, @tr], [], [])

        if rd.include?(@socket)
          http_parser << @socket.read_nonblock(QUANTUM)
        end

        if rd.include?(@tr)
          break
        end
      end

      # Once we're done, close things up.
      finish
    end

    ##
    # @private
    def finish
      @socket.close
      @tr.close
      @tw.close
    end
  end
end
