require 'spec_helper'

require 'couchdb/change_watcher'
require 'thread'

module Couchdb
  describe ChangeWatcher do
    class TestWatcher < Couchdb::ChangeWatcher
      attr_accessor :changes

      def initialize(database, credentials, mutex, cond)
        super(database)

        self.changes = []

        @credentials = credentials
        @mutex = mutex
        @cond = cond
      end

      def customize_request(req)
        req.basic_auth(@credentials[:username], @credentials[:password])
      end

      def process(change)
        changes << change
        change_processed(change)

        @mutex.synchronize { @cond.signal }
      end
    end

    let!(:mutex) { Mutex.new }
    let!(:ready) { ConditionVariable.new }

    let(:database_name) { "catalog_database_#{Rails.env}" }
    let(:database_uri) { instance_uri + "/#{database_name}" }
    let(:db) { Database.new(database_uri) }

    before do
      create_databases!
    end

    after do
      drop_databases!
    end

    it 'receives changes' do
      watcher = TestWatcher.new(db, admin_credentials, mutex, ready)

      db.put('foo', { 'foo' => 'bar' }, admin_credentials)

      mutex.synchronize { ready.wait(mutex, 1) }

      watcher.changes.select { |r| r['id'] == 'foo' }.length.should == 1
    end

    describe '#waiter_for' do
      let!(:watcher) { TestWatcher.new(db, admin_credentials, mutex, ready) }

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
  end
end
