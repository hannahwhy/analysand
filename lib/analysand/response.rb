require 'forwardable'
require 'json/ext'

module Analysand
  ##
  # The response object is a wrapper around Net::HTTPResponse that provides a
  # few amenities:
  #
  # 1. A #success? method, which checks if 200 <= response code <= 299.
  # 2. A #conflict method, which checks if response code == 409.
  # 3. Automatic JSON deserialization of all response bodies.
  # 4. Delegates the [] property accessor to the body.
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

    def conflict?
      code.to_i == 409
    end

    def code
      response.code
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
