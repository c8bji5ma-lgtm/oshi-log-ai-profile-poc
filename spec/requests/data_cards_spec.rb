require "rails_helper"

RSpec.describe "Data cards", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let(:date) { Date.new(2026, 6, 15) }
  let(:oshi) { create(:oshi, name: "登録済みの推し") }

  around { |example| travel_to(Time.zone.local(2026, 6, 15, 12)) { example.run } }
  before do
    create(:profile, user: user)
    login
  end

  def login(account = user)
    post user_session_path, params: { user: { email: account.email, password: "password123" } }
  end

  def generate(**settings)
    post card_path, params: { card: { template: "data", year: "2026", oshi_id: "" }.merge(settings) }, as: :json
  end

  def save(png, receipt)
    post download_card_path, params: png, headers: { "CONTENT_TYPE" => "image/png", "X-Card-Receipt" => receipt }
  end

  def activity(**options)
    create(:activity, user: user, occurred_on: date, **options)
  end

  it "offers Summary years and only registered owned oshis, including ended registrations, with no private data or subscriptions" do
    create(:user_oshi, user: user, oshi: oshi, ended_period: "2025")
    activity(occurred_on: Date.new(2025, 1, 1))
    activity(occurred_on: Date.new(2027, 1, 1))
    create(:activity, occurred_on: Date.new(2024, 1, 1))
    create(:user_oshi)
    get statistics_card_path
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("private", "no-store")
    expect(response.parsed_body).to eq("year" => "2026", "years" => OshiData::Summary.available_years(user: user, date: date).map(&:to_s),
      "oshis" => [ { "id" => oshi.id.to_s, "name" => oshi.name } ])
    delete destroy_user_session_path
    get statistics_card_path
    expect(response).to have_http_status(:unauthorized)
    generate
    expect(response).to have_http_status(:unauthorized)
  end

  it "generates and saves an identical zero-data card without oshis and without DB persistence or image/subscription reads" do
    original = user.profile.reload.attributes
    models = [ Profile, UserOshi, Activity, ActivityOshi, Subscription, ActiveStorage::Blob, ActiveStorage::Attachment ]
    counts = models.map(&:count)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries << payload[:sql] }
    generate
    expect(response).to have_http_status(:ok)
    png = response.body.dup
    receipt = response.headers.fetch("X-Card-Receipt")
    expect(receipt.bytesize).to be < 16.kilobytes
    expect(response.media_type).to eq("image/png")
    expect(response.headers["X-Card-Expires-At"].to_i).to eq(15.minutes.from_now.to_i)
    image = Vips::Image.new_from_buffer(png, "")
    expect([ image.width, image.height ]).to eq([ 1600, 1000 ])
    save(png, receipt)
    ActiveSupport::Notifications.unsubscribe(subscriber)
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(png)
    expect(response.headers["X-PNG-SHA256"]).to eq(Digest::SHA256.hexdigest(png))
    expect(queries.join).not_to match(/\b(?:subscriptions|active_storage_blobs|active_storage_attachments)\b/i)
    expect(models.map(&:count)).to eq(counts)
    expect(user.profile.reload.attributes).to eq(original)
    expect(user.user_oshis).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it "supports past and future choices and signs only the year and single/all scope" do
    create(:user_oshi, user: user, oshi: oshi, ended_period: "2025")
    activity(occurred_on: Date.new(2025, 12, 31))
    activity(occurred_on: Date.new(2027, 1, 1))
    [ "2025", "2026", "2027" ].each do |year|
      generate(year: year, oshi_id: oshi.id.to_s)
      expect(response).to have_http_status(:ok)
      receipt = response.headers.fetch("X-Card-Receipt")
      payload = Rails.application.message_verifier(CardsController::PURPOSE).verified(receipt, purpose: CardsController::PURPOSE)
      expect(payload["settings"]).to eq("template" => "data", "year" => year, "oshi_id" => oshi.id.to_s)
      save(response.body.dup, receipt)
      expect(response).to have_http_status(:ok)
    end
  end

  [ nil, "", "0000", "2024", "2026-01", "26", "2026 ", 2026, [ "2026" ], { year: "2026" } ].each do |year|
    it "rejects malformed or unavailable year #{year.inspect}" do
      generate(year: year)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.headers["X-Card-Receipt"]).to be_nil
    end
  end

  [ nil, "0", "-1", "01", "1.5", "9223372036854775808", 1, [ "1" ], { id: "1" } ].each do |id|
    it "rejects malformed oshi #{id.inspect}" do
      generate(oshi_id: id)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.headers["X-Card-Receipt"]).to be_nil
    end
  end

  [ :crops, :activity_ids, :image_attachment_ids, :image_user_oshi_ids, :user_oshi_ids, :show_introduction, :unexpected ].each do |key|
    it "rejects unrelated parameter #{key}" do
      generate(**{ key => [] })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.headers["X-Card-Receipt"]).to be_nil
    end
  end

  it "rejects foreign and unregistered oshis and requires an explicitly saved profile" do
    foreign = create(:user_oshi)
    [ foreign.oshi, create(:oshi) ].each do |record|
      generate(oshi_id: record.id.to_s)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(record.name)
    end
    user.profile.destroy!
    generate
    expect(response).to have_http_status(:unprocessable_content)
  end

  [ :add, :delete, :date, :amount, :offset, :add_link, :remove_link, :profile, :name, :registration ].each do |change|
    it "rejects download after relevant source change #{change}" do
      first = activity(amount: 1000)
      second_record = activity(amount: 2000)
      selected = first.oshis.first
      registration = create(:user_oshi, user: user, oshi: selected)
      create(:activity_oshi, activity: first) if change == :remove_link
      generate(oshi_id: %i[add_link remove_link name registration].include?(change) ? selected.id.to_s : "")
      expect(response).to have_http_status(:ok)
      png = response.body.dup
      receipt = response.headers.fetch("X-Card-Receipt")
      case change
      when :add then activity(amount: 1000)
      when :delete
        ActivityOshi.where(activity_id: first.id).delete_all
        first.destroy!
      when :date then first.update!(occurred_on: date + 1)
      when :amount then first.update!(amount: 123)
      when :offset
        first.update!(amount: 1500)
        second_record.update!(amount: 1500)
      when :add_link then create(:activity_oshi, activity: first)
      when :remove_link then first.activity_oshis.last.destroy!
      when :profile then user.profile.update!(display_name: "更新後")
      when :name then selected.update!(name: "更新後")
      when :registration then registration.destroy!
      end
      save(png, receipt)
      expect(response).to have_http_status(:conflict)
      expect(response.media_type).to eq("application/json")
    end
  end

  it "rejects a source update during generation and revalidates settings recovered from signatures" do
    allow_any_instance_of(Cards::Data).to receive(:render).and_wrap_original do |original|
      png = original.call
      activity
      png
    end
    generate
    expect(response).to have_http_status(:conflict)
    expect(response.headers["X-Card-Receipt"]).to be_nil
    allow_any_instance_of(Cards::Data).to receive(:render).and_call_original
    generate
    png = response.body.dup
    verifier = Rails.application.message_verifier(CardsController::PURPOSE)
    payload = verifier.verified(response.headers.fetch("X-Card-Receipt"), purpose: CardsController::PURPOSE)
    [ payload["settings"].merge("crops" => []), payload["settings"].merge("year" => "2024"),
      payload["settings"].merge("oshi_id" => create(:oshi).id.to_s) ].each do |settings|
      receipt = verifier.generate(payload.merge("settings" => settings), purpose: CardsController::PURPOSE)
      save(png, receipt)
      expect(response).to have_http_status(:conflict)
    end
  end

  it "preserves signature, exact PNG bytes, identity, session and fifteen minute checks" do
    generate
    png = response.body.dup
    receipt = response.headers.fetch("X-Card-Receipt")
    save(png, receipt.sub(/.$/, "!"))
    expect(response).to have_http_status(:unprocessable_content)
    save(png + "changed", receipt)
    expect(response).to have_http_status(:unprocessable_content)
    travel 15.minutes
    save(png, receipt)
    expect(response).to have_http_status(:gone)
    travel(-15.minutes)
    delete destroy_user_session_path
    login
    save(png, receipt)
    expect(response).to have_http_status(:forbidden)
    delete destroy_user_session_path
    login(create(:user))
    save(png, receipt)
    expect(response).to have_http_status(:forbidden)
  end
end
