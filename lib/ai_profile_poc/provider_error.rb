module AiProfilePoc
  class ProviderError < StandardError
    attr_reader :retryable

    def initialize(code, retryable: false)
      @retryable = retryable
      # Only local error codes, never HTTP bodies, prompts, or credentials.
      super(code)
    end
  end
end
