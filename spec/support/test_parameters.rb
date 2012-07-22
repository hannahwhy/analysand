require 'uri'

module TestParameters
  def admin_username
    'admin'
  end

  def admin_password
    'admin'
  end

  def admin_credentials
    { :username => admin_username, :password => admin_password }
  end

  def member1_username
    'member1'
  end

  def member1_password
    'member1'
  end

  def member1_credentials
    { :username => member1_username, :password => member1_password }
  end

  def instance_uri
    URI('http://localhost:5984')
  end

  def database_name
    'analysand_test'
  end

  def database_uri
    URI("#{instance_uri}/#{database_name}")
  end
end
