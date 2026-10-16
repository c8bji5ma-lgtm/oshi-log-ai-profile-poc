require "json"
require "fileutils"
require_relative "provider_error"

module AiProfilePoc
  class RequestBudget
    def initialize(path:, max_requests: 6, per_minute: 3, clock: -> { Time.now.to_f })
      unless max_requests.is_a?(Integer) && max_requests.between?(1, 20) && per_minute.is_a?(Integer) && per_minute.between?(1, 20)
        raise ArgumentError, "request limits must be integers in 1..20"
      end
      @path, @max_requests, @per_minute, @clock = path, max_requests, per_minute, clock
      @used = 0
    end

    def acquire(provider)
      raise ProviderError, "request_budget_exhausted" if @used >= @max_requests

      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        raw = file.read
        ledger = raw.empty? ? {} : JSON.parse(raw)
        unless ledger.is_a?(Hash) && ledger.values.all? { |values| values.is_a?(Array) && values.all? { |time| time.is_a?(Numeric) && time.finite? } }
          raise ProviderError, "invalid_limiter_state"
        end
        now = @clock.call
        ledger.transform_values! { |values| values.select { |time| time > now - 60 } }
        times = ledger.fetch(provider, [])
        raise ProviderError, "rate_limited" if times.length >= @per_minute

        ledger[provider] = times + [ now ]
        file.rewind
        file.write(JSON.generate(ledger))
        file.truncate(file.pos)
        file.flush
        @used += 1
      end
    rescue JSON::ParserError
      raise ProviderError, "invalid_limiter_state"
    end
  end
end
