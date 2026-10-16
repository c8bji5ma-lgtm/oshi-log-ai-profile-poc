require "rails_helper"

RSpec.describe ActivityEmotion, type: :model do
  let(:emotion) { Emotion.find_by!(name: "嬉しい") }
  let(:activity) { create(:activity) }

  it "requires both associations and rejects duplicate pairs" do
    expect(described_class.new(activity: activity)).not_to be_valid
    expect(described_class.new(emotion: emotion)).not_to be_valid
    described_class.create!(activity: activity, emotion: emotion)
    expect(described_class.new(activity: activity, emotion: emotion)).not_to be_valid
    expect(described_class.create!(activity: create(:activity), emotion: emotion)).to be_persisted
    expect(described_class.create!(activity: activity, emotion: Emotion.find_by!(name: "感動"))).to be_persisted
  end

  it "enforces pair uniqueness at the database level" do
    duplicate = described_class.create!(activity: activity, emotion: emotion).dup
    expect do
      described_class.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  { activity_id: Activity, emotion_id: Emotion }.each do |attribute, model|
    it "enforces NOT NULL and the foreign key for #{attribute}" do
      link = described_class.create!(activity: activity, emotion: emotion)
      expect do
        described_class.transaction(requires_new: true) { link.update_columns(attribute => nil) }
      end.to raise_error(ActiveRecord::NotNullViolation)
      expect do
        described_class.transaction(requires_new: true) { link.update_columns(attribute => model.maximum(:id) + 1) }
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  it "removes only the deleted activity's links and retains the shared master" do
    activity.emotions << emotion
    other = create(:activity, emotions: [ emotion ])
    # ActivityOshi's last-oshi protection is bypassed only on whole-record deletion.
    ActivityOshi.where(activity_id: activity.id).delete_all
    activity.destroy!
    expect(described_class.where(activity_id: activity.id)).to be_empty
    expect(other.reload.emotions).to contain_exactly(emotion)
    expect(Emotion.exists?(emotion.id)).to be(true)
  end
end
