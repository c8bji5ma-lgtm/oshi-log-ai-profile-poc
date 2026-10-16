require_relative "providers/mock"
require_relative "providers/gemini"
require_relative "providers/open_ai"

module AiProfilePoc
  class ProviderFactory
    NAMES = %w[gemini openai].freeze

    def self.build(name:, live: false, env: ENV, transport: Transport.new)
      raise ArgumentError, "unknown provider" unless NAMES.include?(name)
      prefix = name == "openai" ? "OPENAI" : "GEMINI"
      key = env["#{prefix}_API_KEY"]
      return Providers::Mock.new(name: name) unless live && key.is_a?(String) && !key.strip.empty?

      klass = name == "openai" ? Providers::OpenAi : Providers::Gemini
      klass.new(model: env["#{prefix}_MODEL"], api_key: key, transport: transport)
    end
  end
end
