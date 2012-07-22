require 'spec_helper'

module Couchdb
  describe Response do
    let(:database_name) { "catalog_database_#{Rails.env}" }
    let(:database_uri) { instance_uri + "/#{database_name}" }
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
