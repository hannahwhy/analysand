require 'analysand/view_streaming/builder'
require 'fiber'

module Analysand
  # Private: Controls streaming of view data.
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

    # Private: The HTTP response.
    #
    # This is set by Analysand::Database#stream_view.  The #etag and #code
    # methods use this for header information.
    attr_accessor :http_response

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

    def etag
      http_response.get_fields('ETag').first.gsub('"', '')
    end

    def code
      http_response.code
    end

    def success?
      c = code.to_i

      c >= 200 && c <= 299
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
