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
    end

    let(:instance) { Instance.new(instance_uri) }

    describe '#establish_session' do
      describe 'given admin credentials' do
        let(:credentials) { admin_credentials }

        it_should_behave_like 'a session grantor'
      end

      describe 'given member credentials' do
        let(:credentials) { member1_credentials }

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
