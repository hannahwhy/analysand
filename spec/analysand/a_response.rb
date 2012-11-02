require 'spec_helper'

shared_examples_for 'a response' do
  %w(etag success? code).each do |m|
    it "responds to ##{m}" do
      response.should respond_to(m)
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
