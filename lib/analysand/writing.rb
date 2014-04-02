require 'analysand/bulk_response'
require 'analysand/errors'
require 'analysand/response'

module Analysand
  module Writing
    def put(doc_id, doc, credentials = nil, options = {})
      query = options

      Response.new _put(doc_id, credentials, options, json_headers, doc.to_json)
    end

    def put!(doc_id, doc, credentials = nil, options = {})
      put(doc_id, doc, credentials, options).tap do |resp|
        raise ex(DocumentNotSaved, resp) unless resp.success?
      end
    end

    def ensure_full_commit(credentials = nil, options = {})
      Response.new _post('_ensure_full_commit', credentials, options, json_headers, {}.to_json)
    end

    def bulk_docs(docs, credentials = nil, options = {})
      body = { 'docs' => docs }
      body['all_or_nothing'] = true if options[:all_or_nothing]

      BulkResponse.new _post('_bulk_docs', credentials, {}, json_headers, body.to_json)
    end

    def bulk_docs!(docs, credentials = nil, options = {})
      bulk_docs(docs, credentials, options).tap do |resp|
        raise bulk_ex(BulkOperationFailed, resp) unless resp.success?
      end
    end

    def copy(source, destination, credentials = nil)
      headers = { 'Destination' => destination }

      Response.new _copy(source, credentials, {}, headers, nil)
    end

    def put_attachment(loc, io, credentials = nil, options = {})
      query = {}
      headers = {}

      if options[:rev]
        query['rev'] = options[:rev]
      end

      if options[:content_type]
        headers['Content-Type'] = options[:content_type]
      end

      Response.new _put(loc, credentials, query, headers, io.read)
    end

    def delete(doc_id, rev, credentials = nil)
      headers = { 'If-Match' => rev }

      Response.new _delete(doc_id, credentials, {}, headers, nil)
    end

    def delete!(doc_id, rev, credentials = nil)
      delete(doc_id, rev, credentials).tap do |resp|
        raise ex(DocumentNotDeleted, resp) unless resp.success?
      end
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
