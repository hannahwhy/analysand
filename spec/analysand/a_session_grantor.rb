require 'base64'

shared_examples_for 'a session grantor' do
  let(:result) { instance.establish_session(credentials[:username], credentials[:password]) }
  let(:role_locator) do
    lambda { |resp| resp['roles'] }
  end

  before do
    @session, @resp = result
  end

  it 'returns a session and the original response' do
    @session.should_not be_nil
    @resp.should_not be_nil
  end

  describe 'the session object' do
    it 'has the username' do
      @session[:username].should == credentials[:username]
    end

    it 'has the token issuance time' do
      @session[:token] =~ /AuthSession=([^;]+)/

      time_as_hex = Base64.decode64($1).split(':')[1]
      issuance_time = time_as_hex.to_i(16)

      @session[:issued_at].should == issuance_time
    end

    it 'has the user roles' do
      @session[:roles].should == role_locator[JSON.parse(@resp.body)]
    end

    it 'has a session token' do
      @session[:token].should =~ /AuthSession.+/
    end
  end
end
