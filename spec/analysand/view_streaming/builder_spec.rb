require 'spec_helper'

require 'analysand/view_streaming/builder'

module Analysand
  module ViewStreaming
    describe Builder do
      let(:builder) { Builder.new }

      it 'recognizes the "total_rows" key' do
        builder << '{"total_rows":10000}'

        builder.total_rows.should == 10000
      end

      it 'recognizes the "offset" key' do
        builder << '{"offset":20}'

        builder.offset.should == 20
      end

      describe 'for rows' do
        before do
          builder << '{"total_rows":10000,"offset":20,"rows":'
        end

        it 'builds objects' do
          builder << '[{"id":"foo","key":"bar","value":1}]'

          builder.staged_rows.should == [
            { 'id' => 'foo', 'key' => 'bar', 'value' => 1 }
          ]
        end

        it 'builds objects containing other objects' do
          builder << '[{"id":"foo","key":"bar","value":{"total_rows":1}}]'

          builder.staged_rows.should == [
            { 'id' => 'foo',
              'key' => 'bar',
              'value' => {
                 'total_rows' => 1
               }
            }
          ]
        end

        it 'builds objects containing arrays' do
          builder << '[{"id":"foo","key":"bar","value":{"things":[1,2,3]}}]'

          builder.staged_rows.should == [
            { 'id' => 'foo',
              'key' => 'bar',
              'value' => {
                'things' => [1, 2, 3]
              }
            }
          ]
        end
      end

      describe 'given unexpected top-level keys' do
        before do
          builder << '{"total_rows":10000,"offset":20,"rows":[],'
        end

        it 'raises Analysand::UnexpectedViewKey' do
          lambda { builder << '"abc":"def"}' }.should raise_error(Analysand::UnexpectedViewKey)
        end
      end
    end
  end
end
