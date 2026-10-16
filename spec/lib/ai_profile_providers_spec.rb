require "spec_helper"
require "tmpdir"
require "open3"
require_relative "../../lib/ai_profile_poc/comparison"
require_relative "../../lib/ai_profile_poc/provider_factory"

RSpec.describe "Issue #68 provider comparison" do
  let(:fixtures) { File.expand_path("../../docs/ai_profile_poc", __dir__) }
  let(:data) { JSON.parse(File.read(File.join(fixtures, "activities.json"))) }
  let(:metadata) { JSON.parse(File.read(File.join(fixtures, "image_metadata.json"))) }
  let(:json) { File.read(File.join(fixtures, "mocks/live.json")) }
  let(:input) { AiProfilePoc::ComparisonInput.new(data: data, images: metadata, style: "live", mood: "ライブ感を出したい") }
  let(:transport) { instance_double(AiProfilePoc::Transport) }
  let(:pricing) { AiProfilePoc::Pricing.new(input_per_million: "1", output_per_million: "2") }
  let(:budget) { instance_double(AiProfilePoc::RequestBudget, acquire: nil) }
  let(:runner) { AiProfilePoc::Comparison.new(budget: budget, sleeper: ->(_) { }) }

  before do
    # A test must explicitly replace this stub to exercise the HTTP transport.
    allow(Net::HTTP).to receive(:new).and_raise("Unexpected network access")
  end

  def envelope(name, text = json)
    if name == "openai"
      { "status" => "completed", "model" => "returned-openai-model",
        "output" => [ { "type" => "message", "content" => [ { "type" => "output_text", "text" => text } ] } ],
        "usage" => { "input_tokens" => 100, "output_tokens" => 200 } }
    else
      { "modelVersion" => "returned-gemini-model",
        "candidates" => [ { "finishReason" => "STOP", "content" => { "parts" => [ { "text" => text } ] } } ],
        "usageMetadata" => { "promptTokenCount" => 100, "candidatesTokenCount" => 150, "thoughtsTokenCount" => 50 } }
    end
  end

  def provider(name)
    AiProfilePoc::ProviderFactory.build(name: name, live: true, transport: transport,
      env: { "#{name.upcase}_API_KEY" => "test-secret", "#{name.upcase}_MODEL" => "test-model" })
  end

  it "sends the exact same text and schema to both providers, with only text and metadata" do
    requests = {}
    %w[gemini openai].each do |name|
      allow(transport).to receive(:post) do |**request|
        requests[name] = request
        envelope(name)
      end
      result = runner.run(provider: provider(name), input: input, pricing: pricing)
      expect(result["metrics"]).to include("json_valid" => true, "layout_valid" => true,
        "estimated_cost_usd" => 0.0005, "cost_complete" => true, "mode" => "live", "input_sha256" => input.fingerprint)
      expect(result["metrics"]["attempts"].first["usage"]).to eq("input_tokens" => 100, "output_tokens" => 200)
      expect(result["layout"]).to eq(JSON.parse(json))
    end
    gemini, openai = requests.values_at("gemini", "openai")
    expect(gemini[:body]["contents"]).to eq([ { "role" => "user", "parts" => [ { "text" => input.prompt } ] } ])
    expect(openai[:body]["input"]).to eq(input.prompt)
    expect(gemini[:body]["generationConfig"]["responseFormat"]["text"]["schema"]).to eq(openai[:body]["text"]["format"]["schema"])
    expect(openai[:body]).to include("store" => false, "max_output_tokens" => 4096)
    expect(gemini[:body]["generationConfig"]["maxOutputTokens"]).to eq(4096)
    expect(gemini[:headers]).to eq("x-goog-api-key" => "test-secret")
    expect(openai[:headers]).to eq("Authorization" => "Bearer test-secret")
    expect(gemini[:url]).not_to include("test-secret")
    expect(input.prompt).to include('"aspect_ratio":1.5', '"image_ids"')
    expect(input.prompt).not_to include("fictional-user", "owner_id", "inlineData", "input_image", "fileData")
  end

  it "drops extra activity fields instead of forwarding image bytes, paths or private data" do
    data["activities"].first.merge!("images" => "image-bytes", "url" => "https://private.invalid", "memo" => "private-memo")
    expect(input.prompt).not_to include("image-bytes", "private.invalid", "private-memo")
  end

  [ "url", "bytes", "path", "base64" ].each do |key|
    it "rejects image metadata containing #{key}" do
      metadata.first[key] = "private"
      expect { input }.to raise_error(ArgumentError, /metadata/)
    end
  end

  it "validates source ownership, image dimensions, references and unique IDs before an API call" do
    [ -> { data["activities"].first["owner_id"] = "other" },
      -> { metadata.first["width"] = 0 },
      -> { data["activities"].first["image_ids"] = [ "unknown" ] },
      -> { data["activities"] << data["activities"].first.dup } ].each do |edit|
      original_data, original_metadata = Marshal.dump(data), Marshal.dump(metadata)
      edit.call
      expect do
        AiProfilePoc::ComparisonInput.new(data: data, images: metadata, style: "live", mood: "")
      end.to raise_error(ArgumentError)
      data.replace(Marshal.load(original_data))
      metadata.replace(Marshal.load(original_metadata))
    end
  end

  it "changes the common input hash when mood or dimensions change" do
    original = input.fingerprint
    changed = AiProfilePoc::ComparisonInput.new(data: data, images: metadata, style: "live", mood: "雑誌")
    expect(changed.fingerprint).not_to eq(original)
    metadata.first["height"] = 900
    changed = AiProfilePoc::ComparisonInput.new(data: data, images: metadata, style: "live", mood: "ライブ感を出したい")
    expect(changed.fingerprint).not_to eq(original)
  end

  it "uses mocks with no key, and keeps default mode offline even when keys exist" do
    [ [ true, {} ], [ false, { "OPENAI_API_KEY" => "test-secret", "OPENAI_MODEL" => "test-model" } ] ].each do |live, env|
      instance = AiProfilePoc::ProviderFactory.build(name: "openai", live: live, env: env)
      result = runner.run(provider: instance, input: input)
      expect(result["metrics"]).to include("mode" => "mock", "layout_valid" => true, "estimated_cost_usd" => 0.0)
      expect(budget).not_to have_received(:acquire)
    end
  end

  it "requires an explicit model for live mode and rejects unrecognized providers and unsafe model paths" do
    expect { AiProfilePoc::ProviderFactory.build(name: "other") }.to raise_error(ArgumentError)
    [ nil, "../models/unsafe?key=x" ].each do |model|
      expect do
        AiProfilePoc::ProviderFactory.build(name: "openai", live: true, env: { "OPENAI_API_KEY" => "test-secret", "OPENAI_MODEL" => model })
      end.to raise_error(ArgumentError)
    end
  end

  %w[gemini openai].each do |name|
    it "records invalid JSON and keeps usage/cost without retrying for #{name}" do
      allow(transport).to receive(:post).and_return(envelope(name, "not JSON"))
      result = runner.run(provider: provider(name), input: input, pricing: pricing)
      expect(result["metrics"]).to include("json_valid" => false, "layout_valid" => false, "error" => "invalid_json", "estimated_cost_usd" => 0.0005)
      expect(transport).to have_received(:post).once
      expect(result["layout"]).to be_nil
    end

    it "rejects incomplete or refused output for #{name} even if it contains a valid layout" do
      response = envelope(name)
      name == "openai" ? response["status"] = "incomplete" : response["candidates"].first["finishReason"] = "MAX_TOKENS"
      allow(transport).to receive(:post).and_return(response)
      expect(runner.run(provider: provider(name), input: input)["metrics"]).to include("error" => "incomplete_or_refused", "layout_valid" => false)
    end

    it "handles malformed provider envelopes for #{name} without echoing their body" do
      allow(transport).to receive(:post).and_return([ "private response" ])
      metrics = runner.run(provider: provider(name), input: input)["metrics"]
      expect(metrics["error"]).to eq("invalid_response_envelope")
      expect(JSON.generate(metrics)).not_to include("private response", "test-secret")
    end
  end

  it "distinguishes valid JSON with an invalid layout, wrong style or an out-of-source crop" do
    [ ->(value) { value["background"] = "red" },
      ->(value) { value["style"] = "magazine" },
      ->(value) { value["elements"].find { |element| element["type"] == "image" }["crop"]["x"] = 0 } ].each do |edit|
      value = JSON.parse(json)
      edit.call(value)
      allow(transport).to receive(:post).and_return(envelope("openai", JSON.generate(value)))
      expect(runner.run(provider: provider("openai"), input: input)["metrics"]).to include("json_valid" => true, "layout_valid" => false, "error" => "invalid_layout")
    end
  end

  it "bounds retries, counts every attempt, and marks total cost unknown after a timeout" do
    calls = 0
    allow(transport).to receive(:post) do
      calls += 1
      raise AiProfilePoc::ProviderError.new("timeout", retryable: true) if calls == 1
      envelope("openai")
    end
    metrics = runner.run(provider: provider("openai"), input: input, pricing: pricing)["metrics"]
    expect(metrics).to include("layout_valid" => true, "cost_complete" => false, "known_cost_usd" => 0.0005)
    expect(metrics["estimated_cost_usd"]).to be_nil
    expect(metrics["attempts"].length).to eq(2)
    expect(metrics["attempts"].all? { |attempt| attempt["elapsed_ms"] >= 0 }).to be(true)
    expect(budget).to have_received(:acquire).with("openai").twice
    allow(transport).to receive(:post).and_raise(AiProfilePoc::ProviderError.new("http_503", retryable: true))
    metrics = runner.run(provider: provider("openai"), input: input)["metrics"]
    expect(metrics["attempts"].length).to eq(2)
    expect(metrics["error"]).to eq("http_503")
  end

  it "never retries authentication errors or sends requests after the budget is exhausted" do
    allow(transport).to receive(:post).and_raise(AiProfilePoc::ProviderError.new("http_401"))
    expect(runner.run(provider: provider("openai"), input: input)["metrics"]["attempts"].length).to eq(1)
    allow(budget).to receive(:acquire).and_raise(AiProfilePoc::ProviderError.new("rate_limited"))
    expect(runner.run(provider: provider("openai"), input: input)["metrics"]).to include("error" => "rate_limited", "attempts" => [])
    expect(transport).to have_received(:post).once
  end

  it "does not turn missing usage or prices into a zero cost estimate" do
    expect(AiProfilePoc::Pricing.new.estimate("input_tokens" => 100, "output_tokens" => 200)).to be_nil
    expect(pricing.estimate("input_tokens" => 100, "output_tokens" => nil)).to be_nil
    [ "NaN", "Infinity", "-1", "bad" ].each do |value|
      expect { AiProfilePoc::Pricing.new(input_per_million: value) }.to raise_error(ArgumentError)
    end
    allow(transport).to receive(:post).and_return(envelope("openai").merge("usage" => nil))
    metrics = runner.run(provider: provider("openai"), input: input, pricing: pricing)["metrics"]
    expect(metrics).to include("layout_valid" => true, "cost_complete" => false)
    expect(metrics["estimated_cost_usd"]).to be_nil
  end

  it "enforces per-run and shared rolling-minute limits, including across budget instances" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "limits.json")
      now = 100.0
      first = AiProfilePoc::RequestBudget.new(path: path, max_requests: 3, per_minute: 2, clock: -> { now })
      2.times { first.acquire("openai") }
      second = AiProfilePoc::RequestBudget.new(path: path, clock: -> { now }, per_minute: 2)
      expect { second.acquire("openai") }.to raise_error(AiProfilePoc::ProviderError, "rate_limited")
      now = 161.0
      first.acquire("openai")
      expect { first.acquire("gemini") }.to raise_error(AiProfilePoc::ProviderError, "request_budget_exhausted")
      File.write(path, "broken")
      expect { second.acquire("gemini") }.to raise_error(AiProfilePoc::ProviderError, "invalid_limiter_state")
    end
  end

  it "rejects configurations that could disable practical bounds" do
    [ { timeout: 0 }, { timeout: 61 }, { retries: 3 }, { retries: -1 }, { max_output_tokens: 100_000 } ].each do |settings|
      expect { AiProfilePoc::Comparison.new(budget: budget, **settings) }.to raise_error(ArgumentError)
    end
    expect { AiProfilePoc::RequestBudget.new(path: "/unused", max_requests: 0) }.to raise_error(ArgumentError)
  end

  it "runs the CLI offline with six comparable rows and valid common JSON outputs" do
    Dir.mktmpdir do |directory|
      script = File.expand_path("../../script/compare_ai_profile_providers.rb", __dir__)
      stdout, stderr, status = Open3.capture3({ "OPENAI_API_KEY" => "", "GEMINI_API_KEY" => "" },
        RbConfig.ruby, script, "--live", "--output", directory)
      expect(status.success?).to be(true), stderr
      expect(stdout).to include("gemini/mock", "openai/mock")
      rows = File.readlines(File.join(directory, "metrics.jsonl")).map { |line| JSON.parse(line) }
      expect(rows.length).to eq(6)
      rows.group_by { |row| row["style"] }.each_value do |pair|
        expect(pair.map { |row| row["input_sha256"] }.uniq.length).to eq(1)
        expect(pair.map { |row| row["schema_sha256"] }.uniq.length).to eq(1)
        expect(pair.all? { |row| row["layout_valid"] && row["mode"] == "mock" }).to be(true)
      end
      expect(Dir.glob(File.join(directory, "*-*.json")).length).to eq(6)
      _, stderr, repeated = Open3.capture3(RbConfig.ruby, script, "--output", directory)
      expect(repeated.success?).to be(false)
      expect(stderr).to include("output directory must be empty")
      expect(File.readlines(File.join(directory, "metrics.jsonl")).length).to eq(6)
    end
  end
end

RSpec.describe AiProfilePoc::Transport do
  let(:http) { double("HTTP", use_ssl: nil, open_timeout: nil, read_timeout: nil, write_timeout: nil, max_retries: nil) }
  let(:transport) { described_class.new }

  before do
    allow(Net::HTTP).to receive(:new).with("api.openai.com", 443, nil).and_return(http)
    %i[use_ssl= open_timeout= read_timeout= write_timeout= max_retries=].each { |name| allow(http).to receive(name) }
  end

  def request
    transport.post(url: "https://api.openai.com/v1/responses", headers: { "Authorization" => "Bearer test-secret" }, body: { "input" => "fictional" }, timeout: 3)
  end

  it "sets SSL, all timeouts and disables Net::HTTP's internal retries" do
    response = double(code: "200")
    allow(response).to receive(:read_body).and_yield('{"ok":true}')
    allow(http).to receive(:request).and_yield(response)
    expect(request).to eq("ok" => true)
    expect(http).to have_received(:use_ssl=).with(true)
    %i[open_timeout= read_timeout= write_timeout=].each { |name| expect(http).to have_received(name).with(3) }
    expect(http).to have_received(:max_retries=).with(0)
  end

  [ [ "429", true ], [ "503", true ], [ "401", false ], [ "302", false ] ].each do |status, retryable|
    it "classifies HTTP #{status} without including response bodies or following redirects" do
      response = double(code: status)
      allow(response).to receive(:read_body).and_yield("sensitive upstream body test-secret")
      allow(http).to receive(:request).and_yield(response)
      expect { request }.to raise_error(AiProfilePoc::ProviderError) { |error| expect([ error.message, error.retryable ]).to eq([ "http_#{status}", retryable ]) }
      expect(http).to have_received(:request).once
    end
  end

  it "normalizes timeouts and network failures without reflecting their messages" do
    [ Timeout::Error.new("test-secret"), SocketError.new("test-secret") ].each do |error|
      allow(http).to receive(:request).and_raise(error)
      expect { request }.to raise_error(AiProfilePoc::ProviderError) { |failure| expect(failure.message).not_to include("test-secret") }
    end
  end

  it "rejects oversized and malformed responses" do
    response = double(code: "200")
    allow(http).to receive(:request).and_yield(response)
    allow(response).to receive(:read_body).and_yield("x" * (described_class::MAX_RESPONSE_BYTES + 1))
    expect { request }.to raise_error(AiProfilePoc::ProviderError, "response_too_large")
    allow(response).to receive(:read_body).and_yield("bad JSON")
    expect { request }.to raise_error(AiProfilePoc::ProviderError, "invalid_response_envelope")
  end
end
