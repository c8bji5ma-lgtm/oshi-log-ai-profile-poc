class Emotion < ApplicationRecord
  has_many :activity_emotions, dependent: :restrict_with_error
  has_many :activities, through: :activity_emotions

  scope :ordered, -> { order(:position, :id) }

  validates :name, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
