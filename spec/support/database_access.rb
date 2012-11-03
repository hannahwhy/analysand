require 'net/http'

module DatabaseAccess
  ##
  # Sets members and admins for the database.
  #
  # Assumes #admin_credentials returns a Hash containing the keys :username and
  # :password, where those keys' values are the username and password of a
  # CouchDB admin user.
  def set_security(members, admins = {})
    doc = {
      'members' => members,
      'admins' => admins
    }

    credentials = admin_credentials
    uri = instance_uri

    Net::HTTP.start(uri.host, uri.port) do |h|
      req = Net::HTTP::Put.new("/#{database_name}/_security")
      req.basic_auth(credentials[:username], credentials[:password])
      req.body = doc.to_json

      resp = h.request(req)

      unless Net::HTTPSuccess === resp
        raise "Unable to set security parameters on #{database_name}: response code = #{resp.code}, body = #{resp.body}"
      end
    end
  end

  ##
  # Resets member and admin lists for the test database to [].
  def clear_security
    set_security({ 'names' => [], 'roles' => [] },
                 { 'names' => [], 'roles' => [] })
  end
end

# vim:ts=2:sw=2:et:tw=78
