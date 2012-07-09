module Couchdb
  class InvalidURIError < StandardError
  end

  class DatabaseError < StandardError
  end

  class DocumentNotSaved < StandardError
    attr_accessor :response
  end
end
