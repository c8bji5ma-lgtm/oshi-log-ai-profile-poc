require "net/http"
require "timeout"
require "json"
require_relative "provider_error"

module AiProfilePoc
  class Transport
    MAX_RESPONSE_BYTES = 1_048_576

    def post(url:, headers:, body:, timeout:)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port, nil)
      http.use_ssl = true
      http.open_timeout = http.read_timeout = http.write_timeout = timeout
      http.max_retries = 0
      request = Net::HTTP::Post.new(uri.request_uri, headers.merge("Content-Type" => "application/json"))
      request.body = JSON.generate(body)
      text = +""
      status = nil
      Timeout.timeout(timeout) do
        http.request(request) do |response|
          status = response.code.to_i
          response.read_body do |chunk|
            raise ProviderError, "response_too_large" if text.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES
            text << chunk
          end
        end
      end
      unless status&.between?(200, 299)
        raise ProviderError.new("http_#{status}", retryable: [ 429, 500, 502, 503, 504 ].include?(status))
      end
      JSON.parse(text, max_nesting: 30)
    rescue Timeout::Error
      raise ProviderError.new("timeout", retryable: true)
    rescue IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError
      raise ProviderError.new("network_error", retryable: true)
    rescue JSON::ParserError
      raise ProviderError, "invalid_response_envelope"
    end
  end
end
