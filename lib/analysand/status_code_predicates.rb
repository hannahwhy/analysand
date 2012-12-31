module Analysand
  module StatusCodePredicates
    def code
      response.code
    end

    def success?
      c = code.to_i

      c >= 200 && c <= 299
    end

    def unauthorized?
      code.to_i == 401
    end

    def conflict?
      code.to_i == 409
    end
  end
end
