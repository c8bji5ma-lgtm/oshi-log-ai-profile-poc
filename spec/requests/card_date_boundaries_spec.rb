require "rails_helper"

RSpec.describe "Card calendar boundaries", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  [
    [ Time.utc(2026, 12, 31, 14, 59, 59), Date.new(2026, 12, 31), Date.new(2026, 12, 31) ],
    [ Time.utc(2026, 12, 31, 15), Date.new(2026, 12, 31), Date.new(2027, 1, 1) ],
    [ Time.utc(2027, 1, 1), Date.new(2027, 1, 1), Date.new(2027, 1, 1) ],
    [ Time.utc(2026, 6, 30, 14, 59, 59), Date.new(2026, 6, 30), Date.new(2026, 6, 30) ],
    [ Time.utc(2026, 6, 30, 15), Date.new(2026, 6, 30), Date.new(2026, 7, 1) ],
    [ Time.utc(2026, 7, 1), Date.new(2026, 7, 1), Date.new(2026, 7, 1) ]
  ].each do |instant, utc_date, tokyo_date|
    { "UTC" => utc_date, "Asia/Tokyo" => tokyo_date }.each do |zone, expected|
      it "uses Rails Date.current consistently at #{instant.iso8601} in #{zone}" do
        travel_to(instant) do
          Time.use_zone(zone) do
            expect(Date.current).to eq(expected)
            user = create(:user)
            create(:profile, user: user)
            yesterday = create(:activity, user: user, occurred_on: expected - 1)
            today = create(:activity, user: user, occurred_on: expected)
            tomorrow = create(:activity, user: user, occurred_on: expected + 1)
            future = create(:activity, user: user, occurred_on: Date.new(expected.year + 1, 1, 1))
            post user_session_path, params: { user: { email: user.email, password: "password123" } }
            get memories_card_path
            expect(response).to have_http_status(:ok)
            expect(response.parsed_body.fetch("activities").map { |item| item["id"] }).to eq([ today.id.to_s, yesterday.id.to_s ])
            post card_path, params: { card: { template: "memory", activity_ids: [ tomorrow.id.to_s ],
              image_attachment_ids: [ "" ], crops: [ Cards::Crop::DEFAULT ] } }, as: :json
            expect(response).to have_http_status(:not_found)
            get statistics_card_path
            expect(response.parsed_body.fetch("year")).to eq(expected.year.to_s)
            expect(response.parsed_body.fetch("years")).to eq(OshiData::Summary.available_years(user: user, date: expected).map(&:to_s))
            result = Cards::Data.new(user: user, year: expected.year.to_s, oshi_id: "").statistics
            summary = OshiData::Summary.new(user: user, date: expected, year: expected.year)
            expect(result[:period_end]).to eq(expected)
            expect(result[:count]).to eq(expected.yday == 1 ? 1 : 2)
            expect(result[:count]).to eq(summary.activity_count)
            expect(result[:months].first(expected.month).map { |row| row.slice(:month, :count) }).to eq(summary.monthly_activities)
            expect(result[:months].drop(expected.month)).to all(include(future: true, count: nil))
            future_stats = Cards::Data.new(user: user, year: future.occurred_on.year.to_s, oshi_id: "").statistics
            expect(future_stats[:count]).to eq(0)
            expect(future_stats[:period_end]).to eq(Date.new(expected.year + 1, 12, 31))
            expect(future_stats[:months]).to all(include(future: true, count: nil))
            if expected.yday == 1
              past = Cards::Data.new(user: user, year: yesterday.occurred_on.year.to_s, oshi_id: "").statistics
              expect(past[:period_end]).to eq(Date.new(expected.year - 1, 12, 31))
              expect(past[:count]).to eq(1)
              expect(past[:months]).to all(include(future: false))
            end
          end
        end
      end
    end
  end
end
