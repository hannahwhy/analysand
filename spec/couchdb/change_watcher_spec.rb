require 'spec_helper'

require 'couchdb/change_watcher'

module Couchdb
  describe ChangeWatcher do
    class TestWatcher < Couchdb::ChangeWatcher
      attr_accessor :changes

      def initialize(database, credentials)
        super(database)

        self.changes = []

        @credentials = credentials
      end

      def customize_request(req)
        req.basic_auth(@credentials[:username], @credentials[:password])
      end

      def process(change)
        changes << change
        change_processed(change)
      end
    end

    let(:database_name) { "catalog_database_#{Rails.env}" }
    let(:database_uri) { instance_uri + "/#{database_name}" }
    let(:db) { Database.new(database_uri) }

    before do
      create_databases!
    end

    after do
      drop_databases!
    end

    describe '#waiter_for' do
      let!(:watcher) { TestWatcher.new(db, admin_credentials) }

      describe 'if the given document has not been processed' do
        it 'blocks until the document has been processed' do
          waiter = watcher.waiter_for('bar')

          Thread.new do
            db.put('foo', { 'foo' => 'bar' }, admin_credentials)
            db.put('bar', { 'foo' => 'bar' }, admin_credentials)
          end

          waiter.wait

          watcher.changes.detect { |r| r['id'] == 'foo' }.should_not be_nil
        end
      end
    end

    it 'receives changes' do
      watcher = TestWatcher.new(db, admin_credentials)

      waiter = watcher.waiter_for('foo')
      db.put('foo', { 'foo' => 'bar' }, admin_credentials)
      waiter.wait

      watcher.changes.select { |r| r['id'] == 'foo' }.length.should == 1
    end
  end
end
