module Analysand
  class InvalidURIError < StandardError
  end

  class DatabaseError < StandardError
    attr_accessor :response
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
end
