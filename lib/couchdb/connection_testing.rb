module Couchdb
  module ConnectionTesting
    ##
    # Issues a HEAD request to the given URI.  If it responds with a success or
    # redirection code, returns true; otherwise, returns false.
    def test_http_connection(uri)
      begin
        resp = Net::HTTP.start(uri.host, uri.port) { |h| h.head(uri.path) }
      
        case resp
        when Net::HTTPSuccess then true
        when Net::HTTPRedirection then true
        else
          error "Expected HEAD #{uri} to return 200, got #{resp.code} (#{resp.body}) instead"
          false
        end
      rescue => e
        error "#{e.class} (#{e.message}) caught while attempting connection to #{uri}"
        error e.backtrace.join("\n")
        false
      end
    end
  end
end
