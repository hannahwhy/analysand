require 'spec_helper'

shared_examples_for 'a response' do
  %w(success? conflict? unauthorized?
     etag code cookies session_cookie).each do |m|
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

  describe '#unauthorized?' do
    it 'returns true if response code is 401' do
      response.stub!(:code => '401')

      response.should be_unauthorized
    end

    it 'returns false if response code is 200' do
      response.stub!(:code => '200')

      response.should_not be_unauthorized
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

  describe '#session_cookie' do
    describe 'with an AuthSession cookie' do
      let(:cookie) do
        'AuthSession=foobar; Version=1; Expires=Wed, 14 Nov 2012 16:32:04 GMT; Max-Age=600; Path=/; HttpOnly'
      end

      before do
        response.stub!(:cookies => [cookie])
      end

      it 'returns the AuthSession cookie' do
        response.session_cookie.should == 'AuthSession=foobar'
      end
    end

    describe 'without an AuthSession cookie' do
      it 'returns nil' do
        response.session_cookie.should be_nil
      end
    end
  end
end
