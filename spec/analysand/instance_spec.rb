require 'spec_helper'

require 'analysand/errors'
require 'analysand/instance'
require 'uri'
require 'vcr'

require File.expand_path('../../shared/models/a_session_grantor', __FILE__)

module Analysand
  describe Instance do
    describe '#initialize' do
      it 'requires an absolute URI' do
        lambda { Instance.new(URI("/abc")) }.should raise_error(InvalidURIError)
      end
    end

    let(:instance) { Instance.new(instance_uri) }

    describe '#establish_session' do
      describe 'given admin credentials' do
        let(:credentials) { admin_credentials }

        it_should_behave_like 'a session grantor'
      end

      describe 'given member credentials' do
        let(:credentials) { members_credentials['member1'] }

        it_should_behave_like 'a session grantor'
      end

      describe 'given incorrect credentials' do
        it 'returns [nil, response]' do
          session, resp = instance.establish_session('wrong', 'wrong')

          session.should be_nil
          resp.code.should == '401'
        end
      end
    end

    describe '#renew_session' do
      let(:credentials) { admin_credentials }

      before do
        @session, _ = instance.establish_session(credentials[:username], credentials[:password])
      end

      describe 'if CouchDB refreshes the session cookie' do
        around do |example|
          VCR.use_cassette('get_session_refreshes_cookie') { example.call }
        end

        it_should_behave_like 'a session grantor' do
          let(:result) { instance.renew_session(@session) }
          let(:role_locator) do
            lambda { |resp| resp['userCtx']['roles'] }
          end
        end
      end

      describe 'if CouchDB does not refresh the session cookie' do
        around do |example|
          VCR.use_cassette('get_session_does_not_refresh_cookie') { example.call }
        end

        it_should_behave_like 'a session grantor' do
          let(:result) { instance.renew_session(@session) }
          let(:role_locator) do
            lambda { |resp| resp['userCtx']['roles'] }
          end
        end
      end

      describe 'given an invalid session' do
        it 'returns [nil, response]' do
          session, resp = instance.renew_session({ :token => 'AuthSession=wrong' })

          session.should be_nil
          resp.code.should == '400'
        end
      end
    end
  end
end
