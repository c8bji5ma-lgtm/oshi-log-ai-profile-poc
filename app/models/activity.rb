class Activity < ApplicationRecord
  ACTIVITY_TYPES = [
    "ライブ・イベント", "配信視聴", "グッズ購入", "メディア視聴", "その他"
  ].freeze

  belongs_to :user
  has_many :activity_oshis, inverse_of: :activity, autosave: true
  has_many :oshis, through: :activity_oshis
  has_many :activity_emotions, inverse_of: :activity, dependent: :destroy
  has_many :emotions, -> { ordered }, through: :activity_emotions

  has_many_attached :images
  validates :images, image_attachment: true

  validates :occurred_on, presence: true
  validates :title, presence: true, length: { maximum: 255 }
  validates :activity_type, presence: true, length: { maximum: 50 },
    inclusion: { in: ACTIVITY_TYPES }
  validates :place, length: { maximum: 255 }
  validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :activity_oshis, presence: { message: "must include at least one oshi" }
end
