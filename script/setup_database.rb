#!/usr/bin/env ruby

require File.expand_path('../../spec/support/test_parameters', __FILE__)
require 'digest'
require 'json'

include TestParameters

admin_command = ['curl',
                 '-X PUT',
                 %Q{--data-binary \"#{admin_password}\"},
                 "#{instance_uri}/_config/admins/#{admin_username}"
].join(' ')

salt = "ff518dabd59b04b527de7c55179059a46ac54976"

member_doc = {
  "salt" => salt,
  "password_sha" => Digest::SHA1.hexdigest("#{member1_password}#{salt}"),
  "roles" => []
}

member_command = ['curl',
                  '-X PUT',
                  "--data-binary '#{member_doc.to_json}'",
                  "-u #{admin_username}:#{admin_password}",
                  "#{instance_uri}/_users/org.couchdb.user:#{member1_username}"
].join(' ')

db_command = ['curl',
             '-X PUT',
             "-u #{admin_username}:#{admin_password}",
             database_uri.to_s
].join(' ')

[ admin_command,
  member_command,
  db_command
].each do |cmd|
  puts cmd
  system cmd
  puts
end
