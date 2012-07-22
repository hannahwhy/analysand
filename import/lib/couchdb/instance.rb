require 'base64'
require 'couchdb/errors'
require 'net/http/persistent'
require 'uri'

module Couchdb
  ##
  # Wraps a CouchDB instance.
  #
  # This class is meant to be used for interacting with parts of CouchDB that
  # aren't associated with any particular database: session management, for
  # example.  If you're looking to do database operations,
  # Couchdb::Database is where you want to be.
  #
  # Instances MUST be identified by an absolute URI; instantiating this class
  # with a relative URI will raise an exception.
  #
  # Common tasks
  # ============
  #
  # Opening an instance
  # -------------------
  #
  #     instance = Couchdb::Instance(URI('http://localhost:5984'))
  #
  #
  # Pinging an instance
  # -------------------
  #
  #     instance.ping  # => #<Response code=200 ...>
  #
  #
  # Establishing a session
  # ----------------------
  #
  #     session, resp = instance.establish_session('username', 'password')
  #     # for correct credentials:
  #     # => [ {
  #     #         :issued_at => (a UNIX timestamp),
  #     #         :roles => [...roles...],
  #     #         :token => 'AuthSession ...',
  #     #         :username => (the supplied username)
  #     #      },
  #     #      the response
  #     #    ]
  #     #
  #     # for incorrect credentials:
  #     # => [nil, the response]
  #
  # The value in :token should be supplied as a cookie on subsequent requests,
  # and can be passed as a credential when using Couchdb::Database
  # methods, e.g.
  #
  #     db = Couchdb::Database.new(...)
  #     session, resp = instance.establish_session(username, password)
  #
  #     db.put(doc, session[:token])
  #
  #
  # Renewing a session
  # ------------------
  #
  #     auth, _ = instance.establish_session('username', 'password')
  #     # ...time passes...
  #     session, resp = instance.renew_session(auth)
  #
  # Note: CouchDB doesn't always renew a session when asked; see the
  # documentation for #renew_session for more details.
  #
  class Instance
    attr_reader :http
    attr_reader :uri

    def initialize(uri)
      raise InvalidURIError, 'You must supply an absolute URI' unless uri.absolute?

      @http = Net::HTTP::Persistent.new('catalog_database')
      @uri = uri
    end

    def establish_session(username, password)
      path = uri + "/_session"

      req = Net::HTTP::Post.new(path.to_s)
      req.add_field('Content-Type', 'application/x-www-form-urlencoded')
      req.body =
        "name=#{URI.encode(username)}&password=#{URI.encode(password)}"

      resp = http.request path, req

      if Net::HTTPSuccess === resp
        [session(resp), resp]
      else
        [nil, resp]
      end
    end

    ##
    # Attempts to renew a session.
    #
    # If the session was renewed, returns a session information hash identical
    # in form to the hash returned by #establish_session.  If the session was
    # not renewed, returns the passed-in hash.
    #
    #
    # Renewal behavior
    # ================
    #
    # CouchDB will only send a new session cookie if the current time is
    # close enough to the session timeout.  For CouchDB, that means that the
    # current time must be within a 10% timeout window (i.e. time left before
    # timeout < timeout * 0.9).
    def renew_session(old_session)
      path = uri + "/_session"

      req = Net::HTTP::Get.new(path.to_s)
      req.add_field('Cookie', old_session[:token])

      resp = http.request path, req

      if Net::HTTPSuccess === resp
        if !resp.get_fields('Set-Cookie')
          [old_session, resp]
        else
          [session(resp), resp]
        end
      else
        [nil, resp]
      end
    end

    private

    def session(resp)
      token = resp.get_fields('Set-Cookie').
        detect { |c| c =~ /^AuthSession=([^;]+)/i }

      fields = Base64.decode64($1).split(':')
      username = fields[0]
      time = fields[1].to_i(16)

      body = JSON.parse(resp.body)
      roles = body.has_key?('userCtx') ?
        body['userCtx']['roles'] : body['roles']

      { :issued_at => time,
        :roles => roles,
        :token => token,
        :username => username
      }
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
