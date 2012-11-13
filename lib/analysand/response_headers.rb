module Analysand
  module ResponseHeaders
    def etag
      response.get_fields('ETag').first.gsub('"', '')
    end

    def cookies
      response.get_fields('Set-Cookie')
    end
  end
end
