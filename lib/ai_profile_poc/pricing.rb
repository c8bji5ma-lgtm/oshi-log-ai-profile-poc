require "bigdecimal"

module AiProfilePoc
  class Pricing
    attr_reader :rates

    def initialize(input_per_million: nil, output_per_million: nil)
      @rates = [ input_per_million, output_per_million ].map do |value|
        next if value.nil? || value == ""
        number = BigDecimal(value.to_s)
        raise ArgumentError, "prices must be finite and nonnegative" unless number.finite? && number >= 0
        number
      end
    end

    def estimate(usage)
      counts = usage.values_at("input_tokens", "output_tokens")
      return unless rates.all? && counts.all? { |value| value.is_a?(Integer) && value >= 0 }

      (rates.zip(counts).sum { |rate, count| rate * count } / 1_000_000).to_f
    end

    def metadata
      { "input_usd_per_million" => rates[0]&.to_s("F"), "output_usd_per_million" => rates[1]&.to_s("F") }
    end
  end
end
