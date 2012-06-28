require 'uri'

module Couchdb
  ##
  # Methods used by objects that reference databases, viz. Couchdb::Database
  # and Couchdb::ChangeWatcher.
  module DatabaseReference
    attr_reader :uri

    ##
    # @private
    def set_credentials(req, creds)
      return unless creds

      if String === creds
        req.add_field('Cookie', creds)
      elsif creds[:username] && creds[:password]
        req.basic_auth(creds[:username], creds[:password])
      end
    end

    ##
    # @private
    def doc_uri(doc_id)
      URI(uri.to_s + URI.escape(doc_id))
    end
  end
end
