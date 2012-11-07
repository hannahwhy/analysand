module Analysand
  module ResponseHeaders
    def etag
      response.get_fields('ETag').first.gsub('"', '')
    end
  end
end
