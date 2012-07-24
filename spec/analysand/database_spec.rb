require 'spec_helper'

require 'analysand/database'
require 'analysand/errors'
require 'thread'
require 'uri'

module Analysand
  describe Database do
    let(:db) { Database.new(database_uri) }

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

        it 'raises Analysand::DocumentNotSaved' do
          lambda { db.put!(docid, doc, admin_credentials) }.should raise_error(Analysand::DocumentNotSaved)
        end

        it 'includes the response in the exception' do
          begin
            db.put!(docid, doc, admin_credentials)
          rescue Analysand::DocumentNotSaved => e
            code = e.response.code
          end

          code.should == '409'
        end
      end
    end

    describe '#head' do
      before do
        clean_databases!

        db.put!('foo', { 'foo' => 'bar' })
      end

      it 'retrieves the rev of a document' do
        resp = db.head('foo')

        resp.etag.should_not be_empty
      end
    end

    describe '#get!' do
      before do
        clean_databases!

        db.put!('foo', { 'foo' => 'bar' })
      end

      describe 'if the response code is 200' do
        it 'returns the document' do
          db.get!('foo').body['foo'].should == 'bar'
        end
      end

      describe 'if the response code is 404' do
        it 'raises Analysand::CannotAccessDocument' do
          lambda { db.get!('bar') }.should raise_error(Analysand::CannotAccessDocument)
        end

        it 'includes the response in the exception' do
          code = nil

          begin
            db.get!('bar')
          rescue Analysand::CannotAccessDocument => e
            code = e.response.code
          end

          code.should == '404'
        end
      end
    end

    describe '#copy' do
      before do
        clean_databases!
        db.put!('foo', { 'foo' => 'bar' }, admin_credentials)
      end

      it 'copies one doc to another ID' do
        db.copy('foo', 'bar', admin_credentials)

        db.get('bar').body['foo'].should == 'bar'
      end

      it 'returns success when copy succeeds' do
        resp = db.copy('foo', 'bar', admin_credentials)

        resp.should be_success
      end
    end

    describe '#put_attachment' do
      let(:io) { StringIO.new('an attachment') }

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

      before do
        clean_databases!

        db.put_attachment('doc_id/a', io, {}, admin_credentials)
      end

      xit 'permits streaming' do
        resp = db.get_attachment('doc_id/a')

        lambda { resp.read_body { } }.should_not raise_error
      end
    end

    describe '#delete' do
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

    describe '#delete!' do
      let(:docid) { 'abc123' }
      let(:doc) do
        { 'foo' => 'bar' }
      end

      before do
        clean_databases!

        @resp = db.put!(docid, doc, admin_credentials)
      end

      describe 'on success' do
        it 'deletes documents' do
          rev = @resp.body['rev']
          resp = db.delete!(docid, rev, admin_credentials)

          resp.should be_success
        end
      end

      describe 'if the response code is 400' do
        it 'raises Analysand::DocumentNotDeleted' do
          lambda { db.delete!(docid, 'wrong', admin_credentials) }.should raise_error(Analysand::DocumentNotDeleted)
        end

        it 'includes the response in the exception' do
          code = nil

          begin
            db.delete!(docid, 'wrong', admin_credentials)
          rescue Analysand::DocumentNotDeleted => e
            code = e.response.code
          end

          code.should == '400'
        end
      end
    end

    describe '#view' do
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
            'names' => [member1_username],
            'roles' => []
          }
        }

        db.put!('_security', security, admin_credentials)

        resp = db.view('doc/a_view', { :skip => 1 }, member1_credentials)

        resp.code.should == '200'
      end
    end

    describe '#view!' do
      before do
        clean_databases!
      end

      describe 'if the response code is 404' do
        it 'raises Analysand::CannotAccessView' do
          lambda { db.view!('unknown/view') }.should raise_error(Analysand::CannotAccessView)
        end

        it 'includes the response in the exception' do
          code = nil

          begin
            db.view!('unknown/view')
          rescue Analysand::CannotAccessView => e
            code = e.response.code
          end

          code.should == '404'
        end
      end
    end
  end
end
