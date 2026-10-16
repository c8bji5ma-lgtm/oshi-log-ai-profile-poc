require "time"
require_relative "comparison_input"
require_relative "pricing"
require_relative "request_budget"

module AiProfilePoc
  class Comparison
    attr_reader :timeout, :retries, :max_output_tokens

    def initialize(budget:, timeout: 20, retries: 1, max_output_tokens: 4096,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
      unless timeout.is_a?(Numeric) && timeout.finite? && timeout.between?(1, 60) &&
        retries.is_a?(Integer) && retries.between?(0, 2) && max_output_tokens.is_a?(Integer) && max_output_tokens.between?(256, 8192)
        raise ArgumentError, "timeout 1..60, retries 0..2, max_output_tokens 256..8192 required"
      end
      @budget, @timeout, @retries, @max_output_tokens, @clock, @sleeper = budget, timeout, retries, max_output_tokens, clock, sleeper
    end

    def run(provider:, input:, pricing: Pricing.new)
      started = @clock.call
      metrics = { "at" => Time.now.utc.iso8601, "provider" => provider.name, "mode" => provider.mode,
        "requested_model" => provider.model, "style" => input.style, "input_sha256" => input.fingerprint,
        "schema_sha256" => Digest::SHA256.hexdigest(JSON.generate(LayoutSchema.build)),
        "timeout_seconds" => timeout, "retry_limit" => retries, "max_output_tokens" => max_output_tokens,
        "pricing" => pricing.metadata, "json_valid" => nil, "layout_valid" => false, "attempts" => [] }
      layout = nil
      begin
        response = generate(provider, input, pricing, metrics["attempts"])
        metrics["response_model"] = response["model"]
        raise ProviderError, "incomplete_or_refused" unless response["complete"]
        metrics["json_valid"] = false
        JSON.parse(response.fetch("json"), max_nesting: 12)
        metrics["json_valid"] = true
        layout = input.validate(response.fetch("json")).proposal
        metrics["layout_valid"] = true
      rescue JSON::ParserError, TypeError
        metrics["error"] = "invalid_json"
      rescue Layout::Invalid
        metrics["error"] = "invalid_layout"
      rescue ProviderError => error
        metrics["error"] = error.message
      end
      metrics["elapsed_ms"] = ((@clock.call - started) * 1000).round(2)
      costs = metrics["attempts"].map { |attempt| attempt["estimated_cost_usd"] }
      metrics["cost_complete"] = costs.any? && costs.all?
      metrics["known_cost_usd"] = costs.compact.sum.round(10)
      metrics["estimated_cost_usd"] = metrics["known_cost_usd"] if metrics["cost_complete"]
      { "metrics" => metrics, "layout" => layout }
    end

    private
      def generate(provider, input, pricing, attempts)
        (retries + 1).times do |index|
          @budget.acquire(provider.name) if provider.mode == "live"
          attempt = { "index" => index + 1 }
          attempts << attempt
          started = @clock.call
          begin
            response = provider.generate(input: input, max_output_tokens: max_output_tokens, timeout: timeout)
            attempt["usage"] = response.fetch("usage")
            attempt["estimated_cost_usd"] = provider.mode == "mock" ? 0.0 : pricing.estimate(attempt["usage"])
            return response
          rescue ProviderError => error
            attempt["error"] = error.message
            raise unless error.retryable && index < retries
          ensure
            attempt["elapsed_ms"] = ((@clock.call - started) * 1000).round(2)
          end
          @sleeper.call(0.5 * (2 ** index))
        end
      end
  end
end
