Emotion.seed_defaults!

# Known demo passwords must never be created outside development.
load Rails.root.join("db/seeds/development.rb") if Rails.env.development?
