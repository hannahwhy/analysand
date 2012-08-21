module Analysand
  class InvalidURIError < StandardError
  end

  class DatabaseError < StandardError
    attr_accessor :response
  end

  class DocumentNotSaved < StandardError
    attr_accessor :response
  end

  class DocumentNotDeleted < StandardError
    attr_accessor :response
  end

  class CannotAccessDocument < StandardError
    attr_accessor :response
  end

  class CannotAccessView < StandardError
    attr_accessor :response
  end
end
