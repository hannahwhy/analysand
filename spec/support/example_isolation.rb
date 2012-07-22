require File.expand_path('../test_parameters', __FILE__)

##
# CouchDB doesn't implement a commit/rollback scheme like other databases, but
# it would nevertheless still sometimes be nice to be able to isolate
# datastore changes made between tests.
#
# This module provides methods to drop and create databases, which provides a
# slow-yet-effective way of achieving said isolation.  Examples:
#
#     describe Something do
#       let(:database_uri) { 'http://localhost:5984' }
#       let(:database_name) { 'something' }
#
#       before do
#         clean_databases!
#       end
#     end
#
#     describe AnotherThing do
#       let(:database_uri) { 'http://localhost:5984' }
#       let(:database_names) { ['another', 'database'] }
#
#       before do
#         clean_databases!
#       end
#     end
#
# If both database_name and database_names are specified in the same example
# group, the latter will have precedence.
#
#
# Clean databases come with a performance cost
# ============================================
#
# Dropping and creating databases has a real performance cost, so it is
# advised that you only use this when absolutely necessary.  Databases are
# only cleaned when
#
#     clean_databases!
#
# is included in an example group's before block.
module ExampleIsolation
  def clean_databases!
    drop_databases!
    create_databases!
  end

  def drop_databases!
    affected_databases.each do |db|
      uri = instance_uri + "/#{db}"
      credentials = admin_credentials

      Net::HTTP.start(uri.host, uri.port) do |http|
        req = Net::HTTP::Delete.new(uri.path)
        req.basic_auth(admin_username, admin_password)

        http.request(req)
      end
    end
  end

  def create_databases!
    affected_databases.each do |db|
      uri = instance_uri + "/#{db}"
      credentials = admin_credentials

      Net::HTTP.start(uri.host, uri.port) do |http|
        req = Net::HTTP::Put.new(uri.path)
        req.basic_auth(admin_username, admin_password)

        http.request(req)
      end
    end
  end

  def affected_databases
    if respond_to?(:database_name)
      [database_name]
    elsif respond_to?(:database_names)
      database_names
    end.flatten
  end
end

# vim:ts=2:sw=2:et:tw=78
