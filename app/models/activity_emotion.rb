class ActivityEmotion < ApplicationRecord
  belongs_to :activity, inverse_of: :activity_emotions
  belongs_to :emotion

  validates :emotion_id, uniqueness: { scope: :activity_id }
end
