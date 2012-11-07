require 'spec_helper'

shared_examples_for 'a response' do
  %w(etag success? conflict? code).each do |m|
    it "responds to ##{m}" do
      response.should respond_to(m)
    end
  end

  describe '#conflict?' do
    describe 'if response code is 409' do
      before do
        response.stub!(:code => '409')
      end

      it 'returns true' do
        response.should be_conflict
      end
    end

    describe 'if response code is 200' do
      before do
        response.stub!(:code => '200')
      end

      it 'returns false' do
        response.should_not be_conflict
      end
    end
  end

  describe '#etag' do
    it 'returns a string' do
      response.etag.should be_instance_of(String)
    end

    it 'returns ETags without quotes' do
      response.etag.should_not include('"')
    end
  end
end
