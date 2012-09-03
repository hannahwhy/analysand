require 'spec_helper'

require 'analysand/database'
require 'analysand/errors'

module Analysand
  describe Database do
    let(:db) { Database.new(database_uri) }

    let(:doc_id) { 'abc123' }
    let(:doc) do
      { 'foo' => 'bar' }
    end

    before do
      clean_databases!
      clear_security
    end

    shared_examples_for '#put success examples' do
      def put(*args)
        db.send(method, *args)
      end

      it 'creates documents' do
        put(doc_id, doc)

        db.get(doc_id).body['foo'].should == 'bar'
      end

      it 'returns success on document creation' do
        resp = put(doc_id, doc)

        resp.should be_success
      end

      it 'ignores the _id attribute in documents' do
        doc.update('_id' => 'wrong')
        put(doc_id, doc)

        db.get(doc_id).body['foo'].should == 'bar'
        db.get('wrong').should_not be_success
      end

      it 'passes credentials' do
        set_security({ 'users' => [member1_username] })

        put(doc_id, doc, member1_credentials)
        db.get(doc_id).should be_success
      end

      it 'passes the batch option' do
        resp = put(doc_id, doc, nil, :batch => 'ok')

        resp.code.should == '202'
      end

      it 'updates documents' do
        resp = put(doc_id, doc)

        doc['bar'] = 'baz'
        doc['_rev'] = resp['rev']

        put(doc_id, doc)
        db.get(doc_id)['bar'].should == 'baz'
      end

      it 'returns success on document update' do
        resp = put(doc_id, doc)

        doc['bar'] = 'baz'
        doc['_rev'] = resp['rev']

        resp = put(doc_id, doc)
        resp.should be_success
      end

      it 'escapes document IDs' do
        db.put('an ID', doc)

        db.get('an ID').should be_success
      end

      it 'handles URN-like IDs' do
        db.put('org.couchdb.doc:one', doc)

        db.get('org.couchdb.doc:one').should be_success
      end
    end

    describe '#create' do
      before do
        drop_databases!
      end

      it 'creates a database' do
        db.create(admin_credentials)

        db.ping.should be_success
      end

      it 'returns success' do
        db.create(admin_credentials).should be_success
      end
    end

    describe '#drop' do
      it 'drops the database' do
        db.drop(admin_credentials)

        db.ping.should_not be_success
      end

      it 'returns success' do
        db.drop(admin_credentials).should be_success
      end
    end

    describe '#drop!' do
      it 'drops the database' do
        db.drop(admin_credentials)

        db.ping.should_not be_success
      end

      it 'raises Analysand::CannotDropDatabase on failure' do
        lambda { db.drop!(member1_credentials) }.should raise_error(Analysand::CannotDropDatabase)
      end
    end

    describe '#put' do
      it_should_behave_like '#put success examples' do
        let(:method) { :put }
      end

      describe 'on update conflict' do
        before do
          db.put(doc_id, doc)
        end

        it 'returns the error code' do
          resp = db.put(doc_id, doc)

          resp.code.should == '409'
        end

        it 'returns the error body' do
          resp = db.put(doc_id, doc)

          resp.body.should have_key('error')
        end
      end
    end

    describe '#put!' do
      it_should_behave_like '#put success examples' do
        let(:method) { :put! }
      end

      describe 'on update conflict' do
        before do
          db.put(doc_id, doc)
        end

        it 'raises Analysand::DocumentNotSaved' do
          lambda { db.put!(doc_id, doc) }.should raise_error(Analysand::DocumentNotSaved) { |e|
            e.response.code.should == '409'
          }
        end
      end
    end

    describe '#put_attachment' do
      let(:string) { 'an attachment' }
      let(:io) { StringIO.new(string) }

      it 'creates attachments' do
        db.put_attachment("#{doc_id}/attachment", io)

        db.get_attachment("#{doc_id}/attachment").body.should == string
      end

      it 'returns success when the attachment is uploaded' do
        resp = db.put_attachment("#{doc_id}/attachment", io)

        resp.should be_success
      end

      it 'passes credentials' do
        set_security({ 'users' => [member1_username] })

        resp = db.put_attachment("#{doc_id}/a", io, member1_credentials)
        resp.should be_success
      end

      it 'sends the rev of the target document' do
        resp = db.put!(doc_id, doc)
        rev = resp['rev']

        resp = db.put_attachment("#{doc_id}/a", io, nil, :rev => rev)
        resp.should be_success
      end

      it 'sends the content type of the attachment' do
        db.put_attachment("#{doc_id}/a", io, nil, :content_type => 'text/plain')

        type = db.get_attachment("#{doc_id}/a").get_fields('Content-Type')
        type.should == ['text/plain']
      end
    end

    describe '#bulk_docs' do
      let(:doc1) { { '_id' => 'doc1', 'foo' => 'bar' } }
      let(:doc2) { { '_id' => 'doc2', 'bar' => 'baz' } }

      it 'creates many documents' do
        db.bulk_docs([doc1, doc2])

        db.get('doc1')['foo'].should == 'bar'
        db.get('doc2')['bar'].should == 'baz'
      end

      it 'updates many documents' do
        r1 = db.put!('doc1', doc1)
        r2 = db.put!('doc2', doc2)

        doc1['foo'] = 'qux'
        doc2['bar'] = 'quux'
        doc1['_rev'] = r1['rev']
        doc2['_rev'] = r2['rev']

        db.bulk_docs([doc1, doc2])

        db.get('doc1')['foo'].should == 'qux'
        db.get('doc2')['bar'].should == 'quux'
      end

      it 'deletes many documents' do
        r1 = db.put!('doc1', doc1)
        r2 = db.put!('doc2', doc2)

        d1 = { '_id' => 'doc1', '_rev' => r1['rev'], '_deleted' => true }
        d2 = { '_id' => 'doc2', '_rev' => r2['rev'], '_deleted' => true }

        db.bulk_docs([d1, d2])

        db.get('doc1').code.should == '404'
        db.get('doc2').code.should == '404'
      end

      it 'updates and deletes documents' do
        r1 = db.put!('doc1', doc1)
        r2 = db.put!('doc2', doc2)

        d1 = { '_id' => 'doc1', '_rev' => r1['rev'], '_deleted' => true }
        d2 = { '_id' => 'doc2', '_rev' => r2['rev'], 'bar' => 'quux' }

        db.bulk_docs([d1, d2])

        db.get('doc1').code.should == '404'
        db.get('doc2')['bar'].should == 'quux'
      end

      it 'returns success if all operations succeeded' do
        resp = db.bulk_docs([doc1, doc2])

        resp.should be_success
      end

      it 'returns non-success if one operation had an error' do
        db.put!('doc1', doc1)

        resp = db.bulk_docs([doc1, doc2])

        resp.should_not be_success
      end

      it 'passes credentials' do
        set_security({ 'users' => [member1_username] })

        resp = db.bulk_docs([doc1, doc2], member1_credentials)

        resp.should be_success
      end

      it 'operates in non-atomic mode by default' do
        db.put!('doc1', doc1)
        db.bulk_docs([doc1, doc2])

        db.get('doc2').should be_success
      end

      it 'supports all-or-nothing mode' do
        # Force a validation failure to check that all-or-nothing mode is
        # properly enabled.
        db.put!('doc1', doc1)
        db.put!('_design/validation', {
          'validate_doc_update' => 'function(){throw({forbidden: ""});}'
        }, admin_credentials)

        db.bulk_docs([doc1, doc2], nil, :all_or_nothing => true)

        db.get('doc2').code.should == '404'
      end
    end

    describe '#bulk_docs!' do
      let(:doc1) { { '_id' => 'doc1', 'foo' => 'bar' } }
      let(:doc2) { { '_id' => 'doc2', 'bar' => 'baz' } }

      it 'returns success if all operations succeeded' do
        resp = db.bulk_docs!([doc1, doc2])

        resp.should be_success
      end

      describe 'if an operation fails' do
        before do
          doc2['_id'] = 'doc1'
        end

        it 'raises Analysand::BulkOperationFailed' do
          lambda { db.bulk_docs!([doc1, doc2]) }.should raise_error(Analysand::BulkOperationFailed)
        end
      end
    end

    describe '#copy' do
      before do
        db.put!(doc_id, doc)
      end

      it 'copies one doc to another ID' do
        db.copy(doc_id, 'bar')

        db.get('bar')['foo'].should == 'bar'
      end

      it 'returns success if copy succeeds' do
        resp = db.copy(doc_id, 'bar')

        resp.should be_success
      end

      it 'returns failure if copy fails' do
        db.put!('bar', {})
        resp = db.copy(doc_id, 'bar')

        resp.code.should == '409'
      end

      it 'overwrites documents' do
        resp = db.put!('bar', {})
        db.copy(doc_id, "bar?rev=#{resp['rev']}")

        db.get('bar')['foo'].should == 'bar'
      end

      it 'passes credentials' do
        set_security({ 'users' => [member1_username] })

        db.copy(doc_id, 'bar', member1_credentials)
        db.get('bar')['foo'].should == 'bar'
      end

      it 'escapes document IDs in URIs' do
        db.copy(doc_id, 'an ID')

        db.get('an ID')['foo'].should == 'bar'
      end
    end

    shared_examples_for '#delete success examples' do
      let(:rev) { @put_resp['rev'] }

      before do
        @put_resp = db.put!(doc_id, doc)
      end

      def delete(*args)
        db.send(method, *args)
      end

      it 'deletes documents' do
        db.delete(doc_id, rev)

        db.get(doc_id).code.should == '404'
      end

      it 'returns success on deletion' do
        resp = db.delete(doc_id, rev)

        resp.should be_success
      end

      it 'passes credentials' do
        set_security({ 'users' => [member1_username] })

        resp = db.delete(doc_id, rev, member1_credentials)

        resp.should be_success
      end

      it 'escapes document IDs in URIs' do
        @put_resp = db.put!('an ID', doc)

        resp = db.delete('an ID', rev)
        resp.should be_success
      end
    end

    describe '#delete' do
      it_should_behave_like '#delete success examples' do
        let(:method) { :delete }
      end

      describe 'on update conflict' do
        before do
          db.put!(doc_id, doc)
        end

        it 'returns the error code' do
          resp = db.delete(doc_id, nil)

          resp.code.should == '400'
        end

        it 'returns the error body' do
          resp = db.delete(doc_id, nil)

          resp.body.should have_key('error')
        end
      end
    end

    describe '#delete!' do
      it_should_behave_like '#delete success examples' do
        let(:method) { :delete! }
      end

      describe 'on update conflict' do
        before do
          db.put!(doc_id, doc)
        end

        it 'raises Analysand::DocumentNotDeleted' do
          lambda { db.delete!(doc_id, nil) }.should raise_error(Analysand::DocumentNotDeleted) { |e|
            e.response.code.should == '400'
          }
        end
      end
    end
  end
end
