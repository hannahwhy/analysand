require 'analysand/response'

module Analysand
  # Public: Wraps the response from GET /_session.
  #
  # GET /_session can be a bit surprising.  A 200 OK response from _session
  # indicates that the session cookie was well-formed; it doesn't indicate that
  # the session is _valid_.
  #
  # Hence, this class adds a #valid? predicate.
  class SessionResponse < Response
    def valid?
      (uc = body['userCtx']) && uc['name']
    end
  end
end
