require 'spec_helper'

require 'analysand/database'
require 'analysand/response'

require File.expand_path('../a_response', __FILE__)

module Analysand
  describe Response do
    let(:db) { Database.new(database_uri) }

    let(:response) do
      VCR.use_cassette('head_request_with_etag') do
        db.head('abc123', admin_credentials)
      end
    end

    it_should_behave_like 'a response'

    describe '#etag' do
      it 'removes quotes from ETags' do
        response.etag.should == '1-967a00dff5e02add41819138abb3284d'
      end
    end
  end
end
