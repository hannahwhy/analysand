require 'analysand/errors'
require 'analysand/response'

module Analysand
  module Reading
    def get(doc_id, credentials = nil)
      Response.new(_get(doc_id, credentials))
    end

    def get!(doc_id, credentials = nil)
      get(doc_id, credentials).tap do |resp|
        raise ex(CannotAccessDocument, resp) unless resp.success?
      end
    end

    def head(doc_id, credentials = nil)
      Response.new(_head(doc_id, credentials))
    end

    def get_attachment(loc, credentials = nil)
      _get(loc, credentials)
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
