require 'spec_helper'

require 'analysand/database'
require 'analysand/view_response'

require File.expand_path('../a_response', __FILE__)

module Analysand
  describe ViewResponse do
    let(:resp_with_docs) do
      '{"rows": [{"id":"foo","key":"foo","value":{},"doc":{"foo":"bar"}}]}'
    end

    let(:resp_without_docs) do
      '{"rows": [{"id":"foo","key":"foo","value":{}}]}'
    end

    let(:db) { Database.new(database_uri) }

    it_should_behave_like 'a response' do
      let(:response) do
        VCR.use_cassette('view') { db.view('doc/a_view') }
      end
    end

    describe '#docs' do
      describe 'if the view includes docs' do
        subject { ViewResponse.new(double(:body => resp_with_docs)) }

        it 'returns the value of the "doc" key in each row' do
          subject.docs.should == [{'foo' => 'bar'}]
        end
      end

      describe 'if the view does not include docs' do
        subject { ViewResponse.new(double(:body => resp_without_docs)) }

        it 'returns []' do
          subject.docs.should == []
        end
      end
    end

    describe '#keys' do
      describe 'if the view includes docs' do
        subject { ViewResponse.new(double(:body => resp_with_docs)) }

        it 'returns the value of the "key" key in each row' do
          subject.keys.should == ['foo']
        end
      end

      describe 'if the view does not include docs' do
        subject { ViewResponse.new(double(:body => resp_without_docs)) }

        it 'returns []' do
          subject.keys.should == ['foo']
        end
      end
    end
  end
end
