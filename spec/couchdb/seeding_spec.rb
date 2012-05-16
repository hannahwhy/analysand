require 'spec_helper'

require 'couchdb/seeding'
require 'fileutils'
require 'tmpdir'

module Couchdb
  describe Seeding do
    include FileUtils
    include Seeding

    let(:database_name) { 'seeding' }
    let(:root) { Dir.mktmpdir }

    before do
      populate_mock_fs
    end

    after do
      cleanup_mock_fs
    end

    describe '#docs_for' do
      it 'lists documents for a database' do
        docs_for(database_name).should ==
          Dir["#{root}/db/#{database_name}/**/*.yml"].sort.reverse
      end

      it 'strips the name of the current environment if it is suffixed' do
        docs_for("#{database_name}_#{Rails.env}").should ==
          Dir["#{root}/db/#{database_name}/**/*.yml"].sort.reverse
      end
    end

    describe '#design_docs_for' do
      it 'lists design documents for a database' do
        design_docs_for(database_name).should ==
          Dir["#{root}/db/#{database_name}/_design/**/*.yml"]
      end

      it 'strips the name of the current environment if it is suffixed' do
        design_docs_for("#{database_name}_#{Rails.env}").should ==
          Dir["#{root}/db/#{database_name}/_design/**/*.yml"]
      end
    end

    describe '#seed_docs' do
      before do
        drop_databases!
        create_databases!
      end

      it 'creates documents' do
        db = Couchdb::Database.new(instance_uri + "/#{database_name}")

        seed_docs(instance_uri + "/#{database_name}", admin_credentials)

        db.get('doc1').body['foo'].should == 'bar'
        db.get('_design/doc1').body['bar'].should == 'baz'
      end

      it 'updates documents' do
        db = Couchdb::Database.new(instance_uri + "/#{database_name}")

        seed_docs(instance_uri + "/#{database_name}", admin_credentials)

        resps = seed_docs(instance_uri + "/#{database_name}", admin_credentials)
        resps.all?(&:success?).should be_true
      end

      describe 'when a block is given' do
        it 'yields the filename, document ID, and response' do
          statuses = []

          seed_docs(instance_uri + "/#{database_name}", admin_credentials) do |fn, doc_id, resp|
            statuses << [fn, doc_id, resp]
          end

          statuses.length.should == 2
        end
      end
    end

    describe '#seed_design_docs' do
      before do
        drop_databases!
        create_databases!
      end

      it 'creates design documents' do
        db = Couchdb::Database.new(instance_uri + "/#{database_name}")

        seed_design_docs(instance_uri + "/#{database_name}", admin_credentials)

        db.get('_design/doc1').body['bar'].should == 'baz'
        db.get('doc1').code.should == '404'
      end

      it 'updates design documents' do
        db = Couchdb::Database.new(instance_uri + "/#{database_name}")

        seed_design_docs(instance_uri + "/#{database_name}", admin_credentials)

        resps = seed_design_docs(instance_uri + "/#{database_name}", admin_credentials)
        resps.all?(&:success?).should be_true
      end

      describe 'when a block is given' do
        it 'yields the filename, document ID, and response' do
          statuses = []

          seed_design_docs(instance_uri + "/#{database_name}", admin_credentials) do |fn, doc_id, resp|
            statuses << [fn, doc_id, resp]
          end

          statuses.length.should == 1
        end
      end
    end

    def populate_mock_fs
      Dir.chdir(root) do
        mkdir_p "db/seeding/_design"

        File.open('db/seeding/doc1.yml', 'w') { |f| f.write('foo: bar') }
        File.open('db/seeding/_design/doc1.yml', 'w') { |f| f.write('bar: baz') }
      end
    end

    def cleanup_mock_fs
      rm_rf root
    end
  end
end
