class Emotion < ApplicationRecord
  DEFAULT_NAMES = %w[嬉しい 興奮 驚き 感動 幸せ 悔しい 寂しい].freeze

  has_many :activity_emotions, dependent: :restrict_with_error
  has_many :activities, through: :activity_emotions

  scope :ordered, -> { order(:position, :id) }

  validates :name, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.seed_defaults!
    # Insert missing names only; retain existing IDs, positions and activity links.
    insert_all(DEFAULT_NAMES.each_with_index.map { |name, position| { name: name, position: position } }, unique_by: :name)
  end
end
