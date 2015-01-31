require 'json'

##
# Methods to do GET and PUT without any of the extra stuff in Analysand::Http
# or Analysand::Response.
module NetHttpAccess
  def net_http_get(db, doc_id)
    Net::HTTP.get_response(URI.join(db.uri, doc_id))
  end

  def net_http_put!(db, doc_id, doc)
    uri = URI.join(db.uri, doc_id)
    req = Net::HTTP::Put.new(uri)
    req.body = doc.to_json

    resp = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    resp.tap { |r| raise unless Net::HTTPSuccess === r }
  end
end
