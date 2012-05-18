require 'spec_helper'

module Couchdb
  describe ViewResponse do
    describe '#docs' do
      let(:resp_with_docs) do
        '{"rows": [{"id":"foo","key":"foo","value":{},"doc":{"foo":"bar"}}]}'
      end

      let(:resp_without_docs) do
        '{"rows": [{"id":"foo","key":"foo","value":{}}]}'
      end

      describe 'if the view includes docs' do
        subject { ViewResponse.new(stub(:body => resp_with_docs)) }

        it 'returns the value of the "doc" key in each row' do
          subject.docs.should == [{'foo' => 'bar'}]
        end
      end

      describe 'if the view does not include docs' do
        subject { ViewResponse.new(stub(:body => resp_without_docs)) }

        it 'returns []' do
          subject.docs.should == []
        end
      end
    end
  end
end
