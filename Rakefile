#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new

namespace :git do
  desc 'Strip trailing whitespace from tracked source files'
  task :strip_spaces do
    `git ls-files`.split("\n").each do |file|
      puts file

      if `file '#{file}'` =~ /text/
        sh "git stripspace < '#{file}' > '#{file}.out'"
        mv "#{file}.out", file
      end
    end
  end
end

task :default => :spec
