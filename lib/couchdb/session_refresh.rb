require 'couchdb/instance'

module Couchdb
  module SessionRefresh
    ##
    # Given a session information hash, calculates whether the current time is
    # sufficiently close to `timeout`.  If it is, a new session cookie is
    # retrieved from the CouchDB instance at `couchdb_uri` and a new session
    # information hash is returned; otherwise, no cookie is retrieved and
    # `session` is returned.
    #
    # A more precise definition of "sufficiently close"
    # =================================================
    #
    # Given a time of issuance I, a timeout TO, and the current time T, T is
    # sufficiently close to (I + TO) iff
    #
    #     T >= I + .9 * TO
    #
    # i.e. T is within 10% of the timeout time.
    def renew_session(session, timeout, couchdb_uri)
      issued_at = session[:issued_at]

      if Time.now.to_f >= issued_at + (0.9 * timeout)
        instance = Instance.new(couchdb_uri)

        new_session, _ = instance.renew_session(session)
        new_session
      else
        session
      end
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
