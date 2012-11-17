require 'spec_helper'

require 'analysand/errors'
require 'analysand/instance'
require 'uri'
require 'vcr'

require File.expand_path('../a_session_grantor', __FILE__)

module Analysand
  describe Instance do
    describe '#initialize' do
      it 'requires an absolute URI' do
        lambda { Instance.new(URI("/abc")) }.should raise_error(InvalidURIError)
      end

      it 'accepts URIs as strings' do
        uri = 'http://localhost:5984/'

        db = Instance.new(uri)

        db.uri.should == URI(uri)
      end
    end

    let(:instance) { Instance.new(instance_uri) }

    describe '#post_session' do
      describe 'with valid credentials' do
        let(:resp) { instance.post_session(member1_username, member1_password) }

        it 'returns success' do
          resp.should be_success
        end

        it 'returns a session cookie in the response' do
          resp.session_cookie.should_not be_empty
        end
      end

      it 'supports hash credentials' do
        resp = instance.post_session(member1_credentials)

        resp.should be_success
      end

      describe 'with invalid credentials' do
        let(:resp) { instance.post_session(member1_username, 'wrong') }

        it 'does not return success' do
          resp.should_not be_success
        end
      end
    end

    describe '#test_session' do
      describe 'with a valid cookie' do
        let(:resp) { instance.post_session(member1_username, member1_password) }
        let(:cookie) { resp.session_cookie }

        it 'returns success' do
          resp = instance.get_session(cookie)

          resp.should be_success
        end

        it 'returns valid' do
          resp = instance.get_session(cookie)

          resp.should be_valid
        end
      end

      describe 'with an invalid cookie' do
        let(:cookie) { 'AuthSession=YWRtaW46NTBBNDkwRUE6npTfHKz68y5q1FX4pWiB-Lzk5mQ' }

        it 'returns success' do
          resp = instance.get_session(cookie)

          resp.should be_success
        end

        it 'does not return valid' do
          resp = instance.get_session(cookie)

          resp.should_not be_valid
        end
      end

      describe 'with a malformed cookie' do
        let(:cookie) { 'AuthSession=wrong' }

        it 'does not return success' do
          resp = instance.get_session(cookie)

          resp.should_not be_success
        end

        it 'does not return valid' do
          resp = instance.get_session(cookie)

          resp.should_not be_valid
        end
      end
    end

    describe '#get_config' do
      let(:credentials) { admin_credentials }

      it 'retrieves a configuration option' do
        VCR.use_cassette('get_config') do
          instance.get_config('stats/rate', admin_credentials).value.should == '"1000"'
        end
      end

      it 'retrieves many configuration options' do
        VCR.use_cassette('get_many_config') do
          instance.get_config('stats', admin_credentials).value.should == {
            'rate' => '1000',
            'samples' => '[0, 60, 300, 900]'
          }
        end
      end
    end

    describe '#set_config!' do
      it 'raises ConfigurationNotSaved on non-success' do
        VCR.use_cassette('unauthorized_set_config') do
          lambda { instance.set_config!('stats/rate', 1000) }.should raise_error(ConfigurationNotSaved)
        end
      end
    end

    describe '#set_config' do
      let(:credentials) { admin_credentials }

      it 'sets a configuration option' do
        VCR.use_cassette('set_config') do
          instance.set_config('stats/rate', 1200, admin_credentials)
          instance.get_config('stats/rate', admin_credentials).value.should == '"1200"'
        end
      end

      it 'accepts values from get_config' do
        VCR.use_cassette('reload_config') do
          samples = instance.get_config('stats/samples', admin_credentials).value
          instance.set_config('stats/samples', samples, admin_credentials)
          instance.get_config('stats/samples', admin_credentials).value.should == samples
        end
      end
    end
  end
end
