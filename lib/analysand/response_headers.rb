module Analysand
  module ResponseHeaders
    def etag
      response.get_fields('ETag').first.gsub('"', '')
    end

    def cookies
      response.get_fields('Set-Cookie')
    end

    def session_cookie
      return unless (cs = cookies)

      cs.detect { |c| c =~ /^(AuthSession=[^;]+)/i }
      $1
    end
  end
end
