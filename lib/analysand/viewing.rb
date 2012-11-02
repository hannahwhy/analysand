require 'analysand/errors'
require 'analysand/streaming_view_response'
require 'analysand/view_response'
require 'fiber'

module Analysand
  module Viewing
    JSON_VALUE_PARAMETERS = %w(key keys startkey endkey).map(&:to_sym)

    def all_docs(parameters = {}, credentials = nil)
      view('_all_docs', parameters, credentials)
    end

    def all_docs!(parameters = {}, credentials = nil)
      view!('_all_docs', parameters, credentials)
    end

    def view(view_name, parameters = {}, credentials = nil)
      stream = parameters.delete(:stream)
      view_path = expand_view_path(view_name)

      if stream
        stream_view(view_path, parameters, credentials)
      else
        return_view(view_path, parameters, credentials)
      end
    end

    def view!(view_name, parameters = {}, credentials = nil)
      view(view_name, parameters, credentials).tap do |resp|
        raise ex(CannotAccessView, resp) unless resp.success?
      end
    end

    def stream_view(view_path, parameters, credentials)
      StreamingViewResponse.new do |sresp|
        do_view_query(view_path, parameters, credentials) do |resp|
          sresp.http_response = resp
          Fiber.yield
          resp.read_body { |data| Fiber.yield(data) }
        end
      end
    end

    def return_view(view_path, parameters, credentials)
      resp = do_view_query(view_path, parameters, credentials)

      ViewResponse.new resp
    end

    def do_view_query(view_path, parameters, credentials, &block)
      use_post = parameters.delete(:post)

      if use_post
        post_view(view_path, parameters, credentials, block)
      else
        get_view(view_path, parameters, credentials, block)
      end
    end

    def get_view(view_path, parameters, credentials, block)
      encode_parameters(parameters)
      _get(view_path, credentials, parameters, {}, nil, block)
    end

    def post_view(view_path, parameters, credentials, block)
      body = {
        'keys' => parameters.delete(:keys)
      }.reject { |_, v| v.nil? }

      encode_parameters(parameters)

      _post(view_path, credentials, parameters, json_headers, body.to_json, block)
    end

    def encode_parameters(parameters)
      JSON_VALUE_PARAMETERS.each do |p|
        if parameters.has_key?(p)
          parameters[p] = parameters[p].to_json
        end
      end
    end

    def expand_view_path(view_name)
      if view_name.include?('/')
        design_doc, view_name = view_name.split('/', 2)
        "_design/#{design_doc}/_view/#{view_name}"
      else
        view_name
      end
    end
  end
end

# vim:ts=2:sw=2:et:tw=78
