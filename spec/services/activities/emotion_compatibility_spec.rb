require "rails_helper"

RSpec.describe "Activity emotion compatibility" do
  it "preserves activity aggregates and generated memory/data card pixels when tags change" do
    user = create(:user)
    create(:profile, user: user)
    activity = create(:activity, :multiple_oshis, user: user, occurred_on: Date.current, amount: 1200)
    activity.oshis.each { |oshi| create(:user_oshi, user: user, oshi: oshi) }
    memory = -> { Cards::Memory.new(user: user, activity_ids: [ activity.id.to_s ], image_attachment_ids: [ "" ], crops: [ Cards::Crop::DEFAULT ]) }
    data = -> { Cards::Data.new(user: user, year: Date.current.year.to_s, oshi_id: "") }
    original_memory = memory.call.render
    original_data = data.call.render
    original_statistics = data.call.statistics

    [ Emotion.where(name: %w[嬉しい 感動]).ids, [] ].each do |ids|
      Activities::Save.call(activity: activity, emotion_ids: ids)
      summary = OshiData::Summary.new(user: user)
      expect(summary.activity_count).to eq(1)
      expect(summary.activity_amount).to eq(1200)
      expect(summary.common_amount).to eq(1200)
      expect(summary.per_oshi.map { |row| row[:count] }).to eq([ 1, 1 ])
      expect(data.call.statistics).to eq(original_statistics)
      expect(memory.call.render).to eq(original_memory)
      expect(data.call.render).to eq(original_data)
    end
  end
end
