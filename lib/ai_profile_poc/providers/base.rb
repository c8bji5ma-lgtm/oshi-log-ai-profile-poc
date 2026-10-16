require_relative "../transport"
require_relative "../layout_schema"

module AiProfilePoc
  module Providers
    class Base
      attr_reader :model

      def initialize(model:, api_key:, transport: Transport.new)
        raise ArgumentError, "explicit model and API key required" unless model.is_a?(String) && model.match?(/\A[a-zA-Z0-9._-]{1,100}\z/) &&
          api_key.is_a?(String) && !api_key.strip.empty?
        @model, @api_key, @transport = model, api_key, transport
      end

      def mode
        "live"
      end

      def generate(input:, max_output_tokens:, timeout:)
        raise NotImplementedError
      end

      private
        def tokens(value)
          value if value.is_a?(Integer) && value >= 0
        end
    end
  end
end
