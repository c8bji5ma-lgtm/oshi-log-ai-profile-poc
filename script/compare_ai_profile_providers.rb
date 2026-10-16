# No Rails boot, database, or image decoding. Default mode never makes HTTP calls.
require "optparse"
require "securerandom"
require "fileutils"
require_relative "../lib/ai_profile_poc/comparison"
require_relative "../lib/ai_profile_poc/provider_factory"

options = { live: false, provider: "all", style: "all", timeout: 20, retries: 1, max_requests: 6, per_minute: 3, max_output_tokens: 4096 }
parser = OptionParser.new do |args|
  args.banner = "Usage: bundle exec ruby script/compare_ai_profile_providers.rb [options]"
  args.on("--live", "Allow real API requests only when that provider's key is configured") { options[:live] = true }
  args.on("--provider NAME", %w[all gemini openai]) { |value| options[:provider] = value }
  args.on("--style NAME", [ "all", *AiProfilePoc::Layout::STYLES ]) { |value| options[:style] = value }
  args.on("--mood TEXT", "Custom mood; requires a single --style") { |value| options[:mood] = value }
  args.on("--timeout SECONDS", Integer) { |value| options[:timeout] = value }
  args.on("--retries COUNT", Integer) { |value| options[:retries] = value }
  args.on("--max-requests COUNT", Integer) { |value| options[:max_requests] = value }
  args.on("--per-minute COUNT", Integer) { |value| options[:per_minute] = value }
  args.on("--max-output-tokens COUNT", Integer) { |value| options[:max_output_tokens] = value }
  args.on("--output DIRECTORY", "Output directory; the shared request limiter stays in tmp/ai_profile_poc") { |value| options[:output] = value }
end

begin
  parser.parse!
  raise ArgumentError, "unexpected positional arguments" unless ARGV.empty?
  raise ArgumentError, "--mood requires a single --style" if options[:mood] && options[:style] == "all"
  root = File.expand_path("..", __dir__)
  fixtures = File.join(root, "docs/ai_profile_poc")
  data = JSON.parse(File.read(File.join(fixtures, "activities.json")))
  images = JSON.parse(File.read(File.join(fixtures, "image_metadata.json")))
  scenarios = { "live" => "ライブ感を出したい", "magazine" => "落ち着いた雑誌風", "scrapbook" => "カラフルなスクラップブック風" }
  scenarios.select! { |style, _| style == options[:style] } unless options[:style] == "all"
  inputs = scenarios.map do |style, mood|
    AiProfilePoc::ComparisonInput.new(data: data, images: images, style: style, mood: options[:mood] || mood)
  end
  names = options[:provider] == "all" ? AiProfilePoc::ProviderFactory::NAMES : [ options[:provider] ]
  providers = names.map { |name| AiProfilePoc::ProviderFactory.build(name: name, live: options[:live]) }
  prices = names.to_h do |name|
    prefix = name.upcase
    [ name, AiProfilePoc::Pricing.new(input_per_million: ENV["#{prefix}_INPUT_USD_PER_MILLION"],
      output_per_million: ENV["#{prefix}_OUTPUT_USD_PER_MILLION"]) ]
  end
  budget = AiProfilePoc::RequestBudget.new(path: File.join(root, "tmp/ai_profile_poc/request_limits.json"),
    max_requests: options[:max_requests], per_minute: options[:per_minute])
  comparison = AiProfilePoc::Comparison.new(budget: budget, timeout: options[:timeout], retries: options[:retries],
    max_output_tokens: options[:max_output_tokens])
  output = options[:output] || File.join(root, "tmp/ai_profile_poc/comparisons/#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.hex(4)}")
  FileUtils.mkdir_p(output)
  raise ArgumentError, "output directory must be empty" unless Dir.empty?(output)
  failed = false
  File.open(File.join(output, "metrics.jsonl"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |log|
    inputs.each do |input|
      providers.each do |provider|
        result = comparison.run(provider: provider, input: input, pricing: prices.fetch(provider.name))
        metrics = result.fetch("metrics")
        log.puts(JSON.generate(metrics))
        log.flush
        if result["layout"]
          File.write(File.join(output, "#{input.style}-#{provider.name}.json"), JSON.pretty_generate(result["layout"]) + "\n")
        else
          failed = true
        end
        puts "#{provider.name}/#{provider.mode} #{input.style}: valid=#{metrics['layout_valid']} #{metrics['elapsed_ms']}ms cost_usd=#{metrics.fetch('estimated_cost_usd', 'unknown')} #{metrics['error']}"
      end
    end
  end
  puts "Results: #{File.expand_path(output)}"
  exit(failed ? 1 : 0)
rescue ArgumentError, OptionParser::ParseError, KeyError => error
  warn "Configuration error: #{error.message}"
  exit 1
end
