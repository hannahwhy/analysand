require 'analysand/response_headers'
require 'analysand/status_code_predicates'
require 'analysand/view_streaming/builder'
require 'fiber'

module Analysand
  # Public: Controls streaming of view data.
  #
  # This class is meant to be used by Analysand::Database#view.  It exports the
  # same interface as ViewResponse.
  #
  # Examples:
  #
  #     resp = db.view('view/something', :stream => true)
  #
  #     resp.total_rows       # => 1000000
  #     resp.offset           # => 0
  #     resp.rows.take(100)   # => first 100 rows
  class StreamingViewResponse
    include Enumerable
    include ResponseHeaders
    include StatusCodePredicates

    # Internal: The HTTP response.
    #
    # This is set by Analysand::Database#stream_view.  The #etag and #code
    # methods use this for header information.
    attr_accessor :response

    def initialize
      @reader = Fiber.new { yield self; "" }
      @generator = ViewStreaming::Builder.new

      # Analysand::Database#stream_view issues the request.  When the response
      # arrives, it yields control back here.  Subsequent resumes read the
      # body.
      #
      # We do this to provide the response headers as soon as possible.
      @reader.resume
    end

    # Public: Yields documents in the view stream.
    #
    # Note that #docs and #rows advance the same stream, so expect to miss half
    # your rows if you do something like
    #
    #     resp.docs.zip(resp.rows)
    #
    # If this is a problem for you, let me know and we can work out a solution.
    def docs
      to_enum(:get_docs)
    end

    def get_docs
      each { |r| yield r['doc'] if r.has_key?('doc') }
    end

    # Public: Yields document keys from the view stream.
    #
    # Note that #keys and #rows advance the same stream, so expect to miss half
    # your rows if you do something like
    #
    #     resp.keys.zip(resp.rows)
    #
    # If this is a problem for you, let me know and we can work out a solution.
    def keys
      to_enum(:get_keys)
    end

    def get_keys
      each { |r| yield r['key'] if r.has_key?('key') }
    end

    def total_rows
      read until @generator.total_rows

      @generator.total_rows
    end

    def offset
      read until @generator.offset

      @generator.offset
    end

    def read
      @generator << @reader.resume
    end

    def each
      return to_enum unless block_given?

      while @reader.alive?
        read while @reader.alive? && @generator.staged_rows.empty?

        until @generator.staged_rows.empty?
          yield @generator.staged_rows.shift
        end
      end
    end

    def rows
      self
    end
  end
end
