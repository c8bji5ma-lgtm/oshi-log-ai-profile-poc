require_relative "../layout"

module AiProfilePoc
  module Providers
    class Mock
      attr_reader :name

      def initialize(name:)
        @name = name
      end

      def mode
        "mock"
      end

      def model
        "offline-layout-v1"
      end

      def generate(input:, max_output_tokens:, timeout:)
        path = File.expand_path("../../../docs/ai_profile_poc/mocks/#{input.style}.json", __dir__)
        { "json" => File.read(path), "complete" => true, "model" => model,
          "usage" => { "input_tokens" => nil, "output_tokens" => nil } }
      end
    end
  end
end
