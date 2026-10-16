require_relative "base"

module AiProfilePoc
  module Providers
    class OpenAi < Base
      def name
        "openai"
      end

      def generate(input:, max_output_tokens:, timeout:)
        response = @transport.post(url: "https://api.openai.com/v1/responses",
          headers: { "Authorization" => "Bearer #{@api_key}" }, timeout: timeout,
          body: { "model" => model, "input" => input.prompt, "store" => false,
            "max_output_tokens" => max_output_tokens,
            "text" => { "format" => { "type" => "json_schema", "name" => "oshi_layout_v1",
              "strict" => true, "schema" => LayoutSchema.build } } })
        usage = response.fetch("usage", {}) || {}
        output = response.fetch("output", []).select { |item| item["type"] == "message" }.flat_map { |item| item.fetch("content", []) }
        text = output.select { |part| part["type"] == "output_text" }.map { |part| part.fetch("text") }.join
        { "json" => text, "complete" => response["status"] == "completed" && !output.any? { |part| part["type"] == "refusal" },
          "model" => response["model"] || model,
          "usage" => { "input_tokens" => tokens(usage["input_tokens"]), "output_tokens" => tokens(usage["output_tokens"]) } }
      rescue KeyError, TypeError, NoMethodError
        raise ProviderError, "invalid_response_envelope"
      end
    end
  end
end
