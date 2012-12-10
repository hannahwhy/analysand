require 'analysand/config_response'
require 'analysand/errors'
require 'analysand/http'
require 'analysand/response'
require 'analysand/session_response'
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
  #     resp, = instance.post_session('username', 'password')
  #     cookie = resp.session_cookie
  #
  # For harmony, the same credentials hash accepted by database methods is
  # also supported:
  #
  #     resp = instance.post_session(:username => 'username',
  #                                  :password => 'password')
  #
  #
  # resp.success? will be true if the session cookie is not empty, false
  # otherwise.
  #
  #
  # Testing a session cookie for validity
  # -------------------------------------
  #
  #     resp = instance.get_session(cookie)
  #
  # In CouchDB 1.2.0, the response body is a JSON object that looks like
  #
  #       {
  #           "info": {
  #               "authentication_db": "_users",
  #               "authentication_handlers": [
  #                   "oauth",
  #                   "cookie",
  #                   "default"
  #               ]
  #           },
  #           "ok": true,
  #           "userCtx": {
  #               "name": "username",
  #               "roles": ["member"]
  #           }
  #       }
  #
  # resp.valid? will be true if userCtx['name'] is non-null, false otherwise.
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
  #
  # If you want to set configuration and just want to let errors bubble
  # up the stack, you can use the bang-variants:
  #
  #     instance.set_config!('stats/rate', 1000)
  #     # => on non-2xx response, raises ConfigurationNotSaved
  #
  #
  # Other instance-level services
  # -----------------------------
  #
  # CouchDB can be extended with additional service handlers; authentication
  # handlers are a popular example.
  #
  # Instance exposes #get, #put, and #post methods to access arbitrary
  # endpoints.
  #
  # Examples:
  #
  #     instance.get('_log', {}, admin_credentials)
  #     instance.post('_browserid', { 'assertion' => assertion },
  #       { 'Content-Type' => 'application/json' })
  #     instance.put('_config/httpd/bind_address', '192.168.0.1', {},
  #       admin_credentials)
  #
  class Instance
    include Errors
    include Http
    include Rack::Utils

    def initialize(uri)
      init_http_client(uri)
    end

    def get(path, headers = {}, credentials = nil)
      _get(path, credentials, {}, headers)
    end

    def post(path, body = nil, headers = {}, credentials = nil)
      _post(path, credentials, {}, headers, body)
    end

    def put(path, body = nil, headers = {}, credentials = nil)
      _put(path, credentials, {}, headers, body)
    end

    def post_session(*args)
      username, password = if args.length == 2
                             args
                           else
                             h = args.first
                             [h[:username], h[:password]]
                           end

      headers = { 'Content-Type' => 'application/x-www-form-urlencoded' }
      body = build_query('name' => username, 'password' => password)

      Response.new post('_session', body, headers)
    end

    def get_session(cookie)
      headers = { 'Cookie' => cookie }

      SessionResponse.new get('_session', headers)
    end

    def get_config(key, credentials = nil)
      ConfigResponse.new get("_config/#{key}", {}, credentials)
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

      ConfigResponse.new put("_config/#{key}", body, {}, credentials)
    end

    def set_config!(key, value, credentials = nil)
      set_config(key, value, credentials).tap do |resp|
        raise ex(ConfigurationNotSaved, resp) unless resp.success?
      end
    end

    private

    def session(cookie, resp)
      token = cookie.split('=', 2).last
      fields = Base64.decode64(token).split(':')

      username = fields[0]
      time = fields[1].to_i(16)

      roles = resp.body.has_key?('userCtx') ?
        resp.body['userCtx']['roles'] : resp.body['roles']

      { :issued_at => time,
        :roles => roles,
        :token => cookie,
        :username => username
      }
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
