require 'spec_helper'

require 'analysand/database'
require 'analysand/response'

module Analysand
  describe Response do
    let(:db) { Database.new(database_uri) }

    describe '#etag' do
      let(:response) do
        VCR.use_cassette('head_request_with_etag') do
          db.head('abc123', admin_credentials)
        end
      end

      it 'removes quotes from ETags' do
        response.etag.should == '1-967a00dff5e02add41819138abb3284d'
      end
    end
  end
end
