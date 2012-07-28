require 'forwardable'
require 'json/ext'

module Analysand
  ##
  # The response object is a wrapper around Net::HTTPResponse that provides a
  # few amenities:
  #
  # 1. A #success? method.  It returns true if the response code is between
  #    (200..299) and false otherwise.
  # 2. Automatic JSON deserialization of all response bodies.
  # 3. Delegates the [] property accessor to the body.
  class Response
    extend Forwardable

    attr_reader :response
    attr_reader :body

    def_delegators :body, :[]

    def initialize(response)
      @response = response

      if !@response.body.nil? && !@response.body.empty?
        @body = JSON.parse(@response.body)
      end
    end

    def etag
      response.get_fields('ETag').first.gsub('"', '')
    end

    def success?
      c = code.to_i

      c >= 200 && c <= 299
    end

    def code
      response.code
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
