require 'analysand/errors'
require 'analysand/config_response'
require 'analysand/http'
require 'analysand/response'
require 'base64'
require 'net/http/persistent'
require 'rack/utils'
require 'uri'

module Analysand
  ##
  # Wraps a CouchDB instance.
  #
  # This class is meant to be used for interacting with parts of CouchDB that
  # aren't associated with any particular database: session management, for
  # example.  If you're looking to do database operations,
  # Analysand::Database is where you want to be.
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
  #     instance = Analysand::Instance(URI('http://localhost:5984'))
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
  # and can be passed as a credential when using Analysand::Database
  # methods, e.g.
  #
  #     db = Analysand::Database.new(...)
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
  #
  # Getting and setting instance configuration
  # ------------------------------------------
  #
  #     v = instance.get_config('couchdb_httpd_auth/allow_persistent_cookies',
  #       credentials)
  #     v.value # => false
  #
  #     instance.set_config('couchdb_httpd_auth/allow_persistent_cookies',
  #       true, credentials)
  #     # => #<Response code=200 ...>
  #
  #     v = instance.get_config('couchdb_httpd_auth/allow_persistent_cookies',
  #       credentials)
  #     v.value #=> true
  #
  # You can get configuration at any level:
  #
  #     v = instance.get_config('', credentials)
  #     v.body['stats']['rate']  # => "1000", or whatever you have it set to
  #
  # #get_config and #set_config both return Response-like objects.  You can
  # check for failure or success that way:
  #
  #     v = instance.get_config('couchdb_httpd_auth/allow_persistent_cookies')
  #     v.code # => '403'
  #
  #     instance.set_config('couchdb_httpd_auth/allow_persistent_cookies', false)
  #     # => #<Response code=403 ...>
  class Instance
    include Http
    include Rack::Utils

    def initialize(uri)
      raise InvalidURIError, 'You must supply an absolute URI' unless uri.absolute?

      @http = Net::HTTP::Persistent.new('analysand_database')
      @uri = uri

      unless uri.path.end_with?('/')
        uri.path += '/'
      end
    end

    def establish_session(username, password)
      headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
      body = build_query('name' => username, 'password' => password)
      resp = Response.new _post('_session', nil, {}, headers, body)

      if resp.success?
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
      headers = { 'Cookie' => old_session[:token] }
      resp = Response.new _get('_session', nil, {}, headers)

      if resp.success?
        if !resp.cookies
          [old_session, resp]
        else
          [session(resp), resp]
        end
      else
        [nil, resp]
      end
    end

    def get_config(key, credentials = nil)
      ConfigResponse.new _get("_config/#{key}", credentials)
    end

    def set_config(key, value, credentials = nil)
      # This is a bizarre transformation that deserves some explanation.
      #
      # CouchDB configuration is made available as strings containing JSON
      # data.  GET /_config/stats, for example, will return something like
      # this:
      #
      #     {"rate":"1000","samples":"[0, 60, 300, 900]"}
      #
      # However, I'd really like to write
      #
      #     instance.set_config('stats/samples', [0, 60, 300, 900])
      #
      # and I'd also like to be able to use values from get_config directly,
      # just for symmetry:
      #
      #     v = instance1.get_config('stats/samples')
      #     instance2.set_config('stats/samples', v)
      #
      # To accomplish this, we convert non-string values to JSON twice.
      # Strings are passed through.
      body = (String === value) ? value : value.to_json.to_json

      ConfigResponse.new _put("_config/#{key}", credentials, {}, {}, body)
    end

    private

    def session(resp)
      token = resp.cookies.detect { |c| c =~ /^AuthSession=([^;]+)/i }
      fields = Base64.decode64($1).split(':')
      username = fields[0]
      time = fields[1].to_i(16)

      roles = resp.body.has_key?('userCtx') ?
        resp.body['userCtx']['roles'] : resp.body['roles']

      { :issued_at => time,
        :roles => roles,
        :token => token,
        :username => username
      }
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
