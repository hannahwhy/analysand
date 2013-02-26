require 'analysand/response'

module Analysand
  # Public: Wraps responses from /_config.
  #
  # GET/PUT/DELETE /_config does not return a valid JSON object in all cases.
  # This response object therefore does The Simplest Possible Thing and just
  # gives you back the response body as a string.
  class ConfigResponse
    include ResponseHeaders
    include StatusCodePredicates

    attr_reader :response
    attr_reader :body

    alias_method :value, :body

    def initialize(response)
      @response = response
      @body = response.body.chomp
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
