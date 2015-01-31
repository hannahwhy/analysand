$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

require File.expand_path('../support/database_access', __FILE__)
require File.expand_path('../support/example_isolation', __FILE__)
require File.expand_path('../support/net_http_access', __FILE__)
require File.expand_path('../support/test_parameters', __FILE__)

require 'celluloid/autostart'   # for ChangeWatcher specs
require 'vcr'

RSpec.configure do |config|
  config.include DatabaseAccess
  config.include ExampleIsolation
  config.include NetHttpAccess
  config.include TestParameters

  config.around do |example|
    begin
      Celluloid.logger = nil
      Celluloid.boot
      example.call
    ensure
      Celluloid.shutdown
    end
  end
end

VCR.configure do |c|
  c.allow_http_connections_when_no_cassette = true
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
end
