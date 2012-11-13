require 'analysand/response'

module Analysand
  # Public: Wraps responses from /_config.
  #
  # Not all responses from sub-resources of _config return valid JSON objects,
  # but JSON.parse expects to see a full JSON object.  This object implements a
  # bit of a hacky workaround if the body does not start with a '{' and end
  # with a '}', then it is not run through the JSON parser.
  class ConfigResponse < Response
    alias_method :value, :body

    def initialize(response)
      body = response.body.chomp

      if body.start_with?('{') && body.end_with?('}')
        super
      else
        @response = response
        @body = body
      end
    end
  end
end
