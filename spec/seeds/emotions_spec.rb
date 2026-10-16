require "rails_helper"

RSpec.describe "Emotion master seeds", type: :model do
  # A private table starts empty regardless of the test DB's seed state.
  # DDL and data roll back with each example; existing tables/rows are untouched.
  before do
    @original_table_name = Emotion.table_name
    table_name = "emotion_seed_spec_#{SecureRandom.hex(6)}"
    Emotion.connection.create_table(table_name) do |table|
      table.string :name, null: false
      table.integer :position, null: false
      table.timestamps null: false
    end
    Emotion.connection.add_index(table_name, :name, unique: true)
    Emotion.table_name = table_name
  end

  after { Emotion.table_name = @original_table_name }

  def seed_master
    load Rails.root.join("db/seeds.rb")
  end

  it "seeds all seven candidates into an empty schema-created table outside development" do
    expect(Emotion.count).to eq(0)
    counts = [ User.count, Oshi.count, Activity.count ]
    seed_master
    expect(Emotion.ordered.pluck(:name, :position)).to eq([
      [ "嬉しい", 0 ], [ "興奮", 1 ], [ "驚き", 2 ], [ "感動", 3 ],
      [ "幸せ", 4 ], [ "悔しい", 5 ], [ "寂しい", 6 ]
    ])
    expect([ User.count, Oshi.count, Activity.count ]).to eq(counts)
    original = Emotion.order(:id).map(&:attributes)
    seed_master
    expect(Emotion.order(:id).map(&:attributes)).to eq(original)
  end

  it "fills only missing defaults, preserving existing IDs, attributes and custom candidates" do
    existing = Emotion.create!(name: "嬉しい", position: 20)
    custom = Emotion.create!(name: "手入力の感情", position: 21)
    original = [ existing.attributes, custom.attributes ]
    expect { seed_master }.to change(Emotion, :count).by(6)
    expect([ existing.reload.attributes, custom.reload.attributes ]).to eq(original)
    expect(Emotion.where(name: %w[嬉しい 興奮 驚き 感動 幸せ 悔しい 寂しい]).count).to eq(7)
    snapshot = Emotion.order(:id).map(&:attributes)
    seed_master
    expect(Emotion.order(:id).map(&:attributes)).to eq(snapshot)
  end

  context "with explicit per-example master setup" do
    include_context "emotion master data"

    it "prepares every candidate even when the test table started empty" do
      expect(Emotion.ordered.pluck(:name)).to eq(%w[嬉しい 興奮 驚き 感動 幸せ 悔しい 寂しい])
    end
  end
end
