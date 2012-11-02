require 'spec_helper'

require 'analysand/database'
require 'benchmark'

require File.expand_path('../a_response', __FILE__)

module Analysand
  describe Database do
    let(:db) { Database.new(database_uri) }
    let(:row_count) { 10000 }

    before(:all) do
      clean_databases!

      doc = {
        'views' => {
          'a_view' => {
            'map' => %Q{
              function (doc) {
                var i;

                for(i = 0; i < #{row_count}; i++) {
                  emit(doc['_id'], i);
                }
              }
            }
          }
        }
      }

      db.put!('_design/doc', doc, admin_credentials)
      db.put!('abc123', {}, admin_credentials)
    end

    before do
      # make sure the view's built
      db.head('_design/doc/_view/a_view', admin_credentials)
    end

    describe 'the streaming view response' do
      it_should_behave_like 'a response' do
        let(:response) { db.view('doc/a_view', :stream => true) }
      end
    end

    describe '#view in streaming mode' do
      let(:resp) { db.view('doc/a_view', :stream => true) }

      it 'returns all rows in order' do
        resp.rows.map { |r| r['value'] }.should == (0...row_count).to_a
      end

      it 'yields docs' do
        resp = db.view('doc/a_view', :stream => true, :include_docs => true)

        resp.docs.take(10).all? { |d| d.has_key?('_id') }.should be_true
      end

      it 'returns error codes from failures' do
        resp = db.view('doc/nonexistent', :stream => true)

        resp.code.should == '404'
      end

      it 'returns rows as soon as possible' do
        streamed = Benchmark.realtime do
          resp = db.view('doc/a_view', :stream => true)
          resp.rows.take(10)
        end

        read_everything = Benchmark.realtime do
          resp = db.view('doc/a_view')
          resp.rows.take(10)
        end

        streamed.should_not be_within(0.5).of(read_everything)
      end

      it 'returns view metadata' do
        resp = db.view('doc/a_view', :stream => true)

        resp.total_rows.should == row_count
        resp.offset.should == 0
      end

      describe '#each' do
        it 'returns an Enumerator if no block is given' do
          resp = db.view('doc/a_view', :stream => true)

          resp.rows.each.should be_instance_of(Enumerator)
        end
      end
    end
  end
end