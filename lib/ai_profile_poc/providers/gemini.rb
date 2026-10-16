require_relative "base"

module AiProfilePoc
  module Providers
    class Gemini < Base
      def name
        "gemini"
      end

      def generate(input:, max_output_tokens:, timeout:)
        response = @transport.post(url: "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent",
          headers: { "x-goog-api-key" => @api_key }, timeout: timeout,
          body: { "contents" => [ { "role" => "user", "parts" => [ { "text" => input.prompt } ] } ],
            "generationConfig" => { "maxOutputTokens" => max_output_tokens,
              "responseFormat" => { "text" => { "mimeType" => "application/json", "schema" => LayoutSchema.build } } } })
        candidate = response.fetch("candidates", []).first || {}
        parts = candidate.fetch("content", {}).fetch("parts", [])
        usage = response.fetch("usageMetadata", {})
        output = tokens(usage["candidatesTokenCount"])
        thoughts = tokens(usage.fetch("thoughtsTokenCount", 0))
        { "json" => parts.reject { |part| part["thought"] }.filter_map { |part| part["text"] }.join,
          "complete" => candidate["finishReason"] == "STOP", "model" => response["modelVersion"] || model,
          "usage" => { "input_tokens" => tokens(usage["promptTokenCount"]),
            "output_tokens" => (output + thoughts if output && thoughts) } }
      rescue KeyError, TypeError, NoMethodError
        raise ProviderError, "invalid_response_envelope"
      end
    end
  end
end
