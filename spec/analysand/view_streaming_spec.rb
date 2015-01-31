require 'spec_helper'

require 'analysand/database'
require 'benchmark'

require File.expand_path('../a_response', __FILE__)

module Analysand
  describe Database do
    let(:db) { Database.new(database_uri) }
    let(:row_count) { 15000 }

    before do
      WebMock.disable!
    end

    after do
      WebMock.enable!
    end

    before do
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

    shared_examples_for 'a view streamer' do
      def get_view(options = {})
        db.send(method, 'doc/a_view', options)
      end

      describe 'response' do
        it_should_behave_like 'a response' do
          let(:response) { get_view(:stream => true) }
        end
      end

      it 'returns all rows in order' do
        resp = get_view(:stream => true)

        resp.rows.map { |r| r['value'] }.should == (0...row_count).to_a
      end

      it 'yields docs' do
        resp = get_view(:include_docs => true, :stream => true)

        expect(resp.docs.take(10).all? { |d| d.has_key?('_id') }).to eq(true)
      end

      it 'yields keys' do
        resp = get_view(:include_docs => false, :stream => true)
        expect(resp.keys.take(10).each { |k| k }).to eq(['abc123'] * 10)
      end

      xit 'returns rows as soon as possible' do
        # first, make sure the view's built
        db.head('_design/doc/_view/a_view', admin_credentials)

        streamed = Benchmark.realtime do
          resp = get_view(:stream => true)
          resp.rows.take(10)
        end

        read_everything = Benchmark.realtime do
          resp = get_view
          resp.rows.take(10)
        end

        streamed.should_not be_within(0.5).of(read_everything)
      end

      it 'returns view metadata' do
        resp = get_view(:stream => true)

        resp.total_rows.should == row_count
        resp.offset.should == 0
      end

      describe '#each' do
        it 'returns an Enumerator if no block is given' do
          resp = get_view(:stream => true)

          resp.rows.each.should be_instance_of(Enumerator)
        end
      end
    end

    describe '#view in streaming mode' do
      it_should_behave_like 'a view streamer' do
        let(:method) { :view }
      end

      it 'returns error codes from failures' do
        resp = db.view('doc/nonexistent', :stream => true)

        resp.code.should == '404'
      end
    end

    describe '#view! in streaming mode' do
      it_should_behave_like 'a view streamer' do
        let(:method) { :view! }
      end

      it 'raises CannotAccessView on failure' do
        lambda { db.view!('doc/nonexistent', :stream => true) }.should raise_error(CannotAccessView)
      end
    end
  end
end
