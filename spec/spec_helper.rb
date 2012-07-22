$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))

require File.expand_path('../support/example_isolation', __FILE__)
require File.expand_path('../support/test_parameters', __FILE__)

require 'vcr'

RSpec.configure do |config|
  config.include ExampleIsolation
  config.include TestParameters
end

VCR.configure do |c|
  c.allow_http_connections_when_no_cassette = true
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
end

