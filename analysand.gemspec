# -*- encoding: utf-8 -*-
require File.expand_path('../lib/analysand/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["David Yip"]
  gem.email         = ["yipdw@member.fsf.org"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "analysand"
  gem.require_paths = ["lib"]
  gem.version       = Analysand::VERSION

  gem.add_dependency 'celluloid'
  gem.add_dependency 'celluloid-io'
  gem.add_dependency 'http_parser.rb'
  gem.add_dependency 'json'
  gem.add_dependency 'net-http-persistent'
  gem.add_dependency 'rack'
  gem.add_dependency 'yajl-ruby'

  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'vcr'
  gem.add_development_dependency 'webmock'
end
