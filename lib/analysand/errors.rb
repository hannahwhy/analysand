module Analysand
  # Private: Methods to generate exceptions.
  module Errors
    # Instantiates an exception and fills in a response.
    #
    # klass    - the exception class
    # response - the response object that caused the error
    def ex(klass, response)
      klass.new("Expected response to have code 2xx, got #{response.code} instead").tap do |ex|
        ex.response = response
      end
    end
  end

  class InvalidURIError < StandardError
  end

  class DatabaseError < StandardError
    attr_accessor :response
  end

  class ConfigurationNotSaved < DatabaseError
  end

  class DocumentNotSaved < DatabaseError
  end

  class DocumentNotDeleted < DatabaseError
  end

  class CannotAccessDocument < DatabaseError
  end

  class CannotAccessView < DatabaseError
  end

  class CannotDropDatabase < DatabaseError
  end

  class BulkOperationFailed < DatabaseError
  end

  class UnexpectedViewKey < StandardError
  end
end
