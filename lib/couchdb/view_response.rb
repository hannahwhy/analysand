require 'couchdb/response'

module Couchdb
  ##
  # A subclass of Response with additional view-specific accessors: total_rows,
  # offset, and rows.
  class ViewResponse < Response
    def total_rows
      body['total_rows']
    end

    def offset
      body['offset']
    end

    def rows
      body['rows']
    end
  end
end
