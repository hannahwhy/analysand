require 'spec_helper'

require 'couchdb/session_refresh'
require 'catalog/settings'
require 'timecop'

module Couchdb
  describe SessionRefresh do
    subject { Object.new.extend(SessionRefresh) }
    let(:timestamp) { 1234567890 }
    let(:timeout) { Catalog::Settings.couchdb.session_timeout }
    let(:uri) { Catalog::Settings.couchdb_uri }

    describe '#renew_session' do
      before do
        Timecop.freeze(Time.at(timestamp))
      end

      after do
        Timecop.return
      end

      describe 'if the current time is not within 10% of the expiration time' do
        let(:session) do
          { :issued_at => timestamp }
        end

        it 'returns the given session information' do
          subject.renew_session(session, timeout, uri).should == session
        end
      end

      describe 'if the current time is within 10% of the expiration time' do
        let(:session) do
          { :issued_at => timestamp,
            :token => 'AuthSession=abcdef'
          }
        end

        let(:threshold) { (timestamp + (0.9 * timeout)).to_i }

        before do
          Timecop.travel(threshold)
        end

        it 'renews the session' do
          new_session = stub
          instance = mock

          instance.should_receive(:renew_session).and_return([new_session, stub])
          Instance.stub(:new => instance)

          subject.renew_session(session, timeout, uri).should == new_session
        end
      end
    end
  end
end
