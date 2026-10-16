require "rails_helper"

RSpec.describe Emotion, type: :model do
  it "provides the seven initial candidates in display order" do
    expect(described_class.ordered.pluck(:name)).to eq(%w[嬉しい 興奮 驚き 感動 幸せ 悔しい 寂しい])
  end

  it "requires a nonblank unique name and a nonnegative integer position" do
    [ nil, "", " ", "嬉しい" ].each do |name|
      expect(described_class.new(name: name, position: 0)).not_to be_valid
    end
    [ nil, -1, 1.5, "abc" ].each do |position|
      expect(described_class.new(name: "追加候補", position: position)).not_to be_valid
    end
    expect(described_class.new(name: "追加候補", position: 7)).to be_valid
  end

  it "exposes activities and prevents deleting an in-use candidate" do
    emotion = described_class.find_by!(name: "嬉しい")
    activity = create(:activity, emotions: [ emotion ])
    expect(emotion.activities).to contain_exactly(activity)
    expect(emotion.destroy).to be(false)
    expect(activity.reload.emotions).to contain_exactly(emotion)
  end

  it "enforces name uniqueness and required columns in the database" do
    emotion = described_class.first
    expect do
      described_class.transaction(requires_new: true) { emotion.dup.save!(validate: false) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
    [ :name, :position ].each do |attribute|
      expect do
        described_class.transaction(requires_new: true) { emotion.update_columns(attribute => nil) }
      end.to raise_error(ActiveRecord::NotNullViolation)
    end
  end
end
