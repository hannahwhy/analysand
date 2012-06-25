require 'spec_helper'

require 'couchdb/database'
require 'couchdb/errors'
require 'thread'
require 'uri'

module Couchdb
  describe Database do
    let(:database_name) { "catalog_database_#{Rails.env}" }
    let(:database_uri) { instance_uri + "/#{database_name}" }

    describe '#initialize' do
      it 'requires an absolute URI' do
        lambda { Database.new(URI("/abc")) }.should raise_error(InvalidURIError)
      end
    end

    describe '.create!' do
      before do
        drop_databases!
      end

      it 'creates the database at the given URI' do
        db = Database.create!(database_uri, admin_credentials)

        resp = db.ping
        resp.body['db_name'].should == database_name
      end

      it 'raises an exception if the database cannot be created' do
        Database.create!(database_uri, admin_credentials)

        lambda { Database.create!(database_uri, admin_credentials) }.should raise_error(DatabaseError)
      end
    end

    describe '.drop' do
      before do
        create_databases!
      end

      it 'drops the database at the given URI' do
        resp = Database.drop(database_uri, admin_credentials)

        resp.should be_success
        Database.new(database_uri).ping.code.should == '404'
      end
    end

    describe '#close' do
      it "shuts down the current thread's connection" do
        pending 'a good way to test this'
      end
    end

    describe '#put' do
      let(:db) { Database.new(database_uri) }
      let(:docid) { 'abc123' }
      let(:doc) do
        { 'foo' => 'bar' }
      end

      before do
        clean_databases!
      end

      it 'creates documents' do
        resp = db.put(docid, doc, admin_credentials)

        db.get(resp.body['id']).body['foo'].should == 'bar'
      end

      it 'returns success on document creation' do
        resp = db.put(docid, doc, admin_credentials)

        resp.should be_success
      end

      it 'does not require credentials' do
        lambda { db.put(docid, doc) }.should_not raise_error(ArgumentError)
      end

      it 'passes the batch option' do
        resp = db.put(docid, doc, admin_credentials, :batch => 'ok')

        resp.code.should == '202'
      end

      it 'updates documents' do
        resp = db.put(docid, doc, admin_credentials)
        rev = resp.body['rev']

        doc.update('foo' => 'baz', '_rev' => rev)
        resp = db.put(docid, doc, admin_credentials)

        db.get(resp.body['id']).body['foo'].should == 'baz'
      end

      it 'returns success on document update' do
        resp = db.put(docid, doc, admin_credentials)
        rev = resp.body['rev']

        resp = db.put(docid, doc.merge('_rev' => rev), admin_credentials)
        resp.should be_success
      end

      it 'escapes document IDs in URIs' do
        db.put('an ID', doc, admin_credentials)

        db.get('an ID').body['foo'].should == 'bar'
      end

      it 'gives the docid in the argument list precedence' do
        db.put('right', doc.merge('_id' => 'wrong'), admin_credentials)

        db.get('right').should be_success
        db.get('wrong').should_not be_success
      end
    end

    describe '#put!' do
      let(:db) { Database.new(database_uri) }
      let(:docid) { 'abc123' }
      let(:doc) do
        { 'foo' => 'bar' }
      end

      before do
        clean_databases!
      end

      describe 'if the response code is 201' do
        it 'returns the response' do
          resp = db.put!(docid, doc, admin_credentials)

          resp.code.should == '201'
        end
      end

      describe 'if the response code is 202' do
        it 'returns the response' do
          resp = db.put!(docid, doc, admin_credentials, :batch => 'ok')

          resp.code.should == '202'
        end
      end

      describe 'if the response code is 409' do
        before do
          db.put!(docid, doc, admin_credentials)
        end

        it 'raises Couchdb::DocumentNotSaved' do
          lambda { db.put!(docid, doc, admin_credentials) }.should raise_error(Couchdb::DocumentNotSaved)
        end

        it 'includes the response in the exception' do
          begin
            db.put!(docid, doc, admin_credentials)
          rescue Couchdb::DocumentNotSaved => e
            code = e.response.code
          end

          code.should == '409'
        end
      end
    end

    describe '#put_attachment' do
      let(:io) { StringIO.new('an attachment') }
      let(:db) { Database.new(database_uri) }

      before do
        clean_databases!
      end

      it 'returns success on attachment creation' do
        resp = db.put_attachment('doc_id/a', io, admin_credentials)

        resp.should be_success
      end

      it 'puts an attachment on a document' do
        db.put_attachment('doc_id/a', io, admin_credentials)

        db.get_attachment('doc_id/a').body.should == 'an attachment'
      end

      it 'sends rev' do
        resp = db.put_attachment('doc_id/a', io, admin_credentials)
        rev = resp.body['rev']
        io2 = StringIO.new('an updated attachment')

        db.put_attachment('doc_id/a', io2, admin_credentials, :rev => rev)
        db.get_attachment('doc_id/a').body.should == 'an updated attachment'
      end

      it 'sends content-type' do
        opts = { :content_type => 'text/plain' }

        db.put_attachment('doc_id/a', io, admin_credentials, opts)
        db.get_attachment('doc_id/a').get_fields('Content-Type').should == ['text/plain']
      end
    end

    describe '#get_attachment' do
      let(:io) { StringIO.new('an attachment') }
      let(:db) { Database.new(database_uri) }

      before do
        clean_databases!

        db.put_attachment('doc_id/a', io, {}, admin_credentials)
      end

      it 'permits streaming' do
        resp = db.get_attachment('doc_id/a')

        lambda { resp.read_body { } }.should_not raise_error
      end
    end

    describe '#delete' do
      let(:db) { Database.new(database_uri) }
      let(:docid) { 'abc123' }
      let(:doc) do
        { 'foo' => 'bar' }
      end

      before do
        clean_databases!

        @resp = db.put(docid, doc, admin_credentials)
      end

      it 'deletes documents' do
        rev = @resp.body['rev']
        resp = db.delete(docid, rev, admin_credentials)

        db.get(@resp.body['id']).code.should == '404'
      end

      it 'returns success on deletion' do
        rev = @resp.body['rev']
        resp = db.delete(docid, rev, admin_credentials)

        resp.should be_success
      end

      it 'escapes document IDs in URIs' do
        resp = db.put('an ID', doc, admin_credentials)
        rev = resp.body['rev']

        db.delete('an ID', rev, admin_credentials)

        db.get('an ID').code.should == '404'
      end
    end

    describe '#view' do
      let(:db) { Database.new(database_uri) }

      before do
        clean_databases!

        doc = {
          'views' => {
            'a_view' => {
              'map' => %q{function (doc) { emit(doc['_id'], 1); }}
            },
            'composite_key' => {
              'map' => %q{function (doc) { emit([1, doc['_id']], 1); }}
            }
          }
        }

        db.put('_design/doc', doc, admin_credentials)
        db.put('abc123', {}, admin_credentials)
        db.put('abc456', {}, admin_credentials)
      end

      it 'retrieves a view' do
        resp = db.view('doc/a_view')

        resp.code.should == '200'
        resp.total_rows.should == resp.body['total_rows']
        resp.offset.should == resp.body['offset']
        resp.rows.should == resp.body['rows']
      end

      it 'passes through view parameters' do
        resp = db.view('doc/a_view', :skip => 1)

        resp.offset.should == 1
        resp.rows.length.should == 1
      end

      it 'JSON-encodes the key parameter' do
        resp = db.view('doc/composite_key', :key => [1, 'abc123'])

        resp.code.should == '200'
        resp.rows.length.should == 1
      end

      it 'JSON-encodes the keys parameter' do
        resp = db.view('doc/composite_key', :keys => [[1, 'abc123'], [1, 'abc456']])

        resp.code.should == '200'
        resp.rows.length.should == 2
      end

      it 'JSON-encodes the startkey parameter' do
        resp = db.view('doc/composite_key', :startkey => [1, 'abc123'])

        resp.code.should == '200'
        resp.rows.length.should == 2
      end

      it 'JSON-encodes the endkey parameter' do
        resp = db.view('doc/composite_key', :endkey => [1, 'abc456'], :skip => 1)

        resp.code.should == '200'
        resp.rows.length.should == 1
      end

      it 'passes credentials' do
        security = {
          'members' => {
            'names' => ['member1'],
            'roles' => []
          }
        }

        db.put('_security', security, admin_credentials)

        resp = db.view('doc/a_view', { :skip => 1 }, members_credentials['member1'])

        resp.code.should == '200'
      end
    end

    describe '#changes' do
      let!(:results) { [] }
      let!(:mutex) { Mutex.new }
      let!(:ready) { ConditionVariable.new }
      let(:db) { Database.new(database_uri) }

      before do
        create_databases!
      end

      after do
        @watcher.stop if @watcher

        drop_databases!
      end

      it 'receives changes' do
        @watcher = db.changes({}, admin_credentials) do |change|
          results << change
          mutex.synchronize { ready.signal }
        end

        db.put('foo', { 'foo' => 'bar' }, admin_credentials)

        mutex.synchronize { ready.wait(mutex, 1) }

        results.select { |r| r['id'] == 'foo' }.length.should == 1
      end

      it 'applies filters' do
        filter = %Q{
          function(doc, req) {
            return doc['test'];
          }
        }

        db.put('_design/doc', { 'filters' => { 'test' => filter } }, admin_credentials)

        @watcher = db.changes({ :filter => 'doc/test' }, admin_credentials) do |change|
          results << change
          mutex.synchronize { ready.signal }
        end

        db.put('foo', { 'test' => true }, admin_credentials)

        mutex.synchronize { ready.wait(mutex, 1) }

        results.length.should == 1
        results.first['id'].should == 'foo'
      end

      it 'applies a seq limit' do
        current_seq = db.status['update_seq']

        @watcher = db.changes({ :since => current_seq }, admin_credentials) do
          results << change
          mutex.synchronize { ready.signal }
        end

        db.put('foo', { 'foo' => 'bar' }, admin_credentials)

        mutex.synchronize { ready.wait(mutex, 1) }

        results.length.should == 1
      end
    end
  end
end
