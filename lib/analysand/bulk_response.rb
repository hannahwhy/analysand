require 'analysand/response'

module Analysand
  ##
  # A subclass of Response that adjusts success? to check for individual error
  # records.
  class BulkResponse < Response
    def success?
      super && body.none? { |r| r.has_key?('error') }
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
