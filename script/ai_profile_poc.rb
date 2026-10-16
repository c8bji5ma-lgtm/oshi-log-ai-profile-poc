# Run with bundle exec ruby script/ai_profile_poc.rb (no Rails boot or database).
require "json"
require "fileutils"
require "digest"
require_relative "../lib/ai_profile_poc/layout"
require_relative "../lib/ai_profile_poc/renderer"
require_relative "../lib/ai_profile_poc/dummy_images"

root = File.expand_path("..", __dir__)
fixtures = File.join(root, "docs/ai_profile_poc")
output = File.join(root, "tmp/ai_profile_poc")
FileUtils.mkdir_p(output)
data = JSON.parse(File.read(File.join(fixtures, "activities.json")))
images = AiProfilePoc::DummyImages.build
before = images.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) }
images.each { |id, bytes| File.binwrite(File.join(output, "#{id}.png"), bytes) }

AiProfilePoc::Layout::STYLES.each do |style|
  layout = AiProfilePoc::Layout.new(json: File.read(File.join(fixtures, "mocks/#{style}.json")),
    owner_id: data.fetch("owner_id"), activities: data.fetch("activities"), image_ids: images.keys)
  png = AiProfilePoc::Renderer.new(layout: layout, images: images).render
  path = File.join(output, "#{style}.png")
  File.binwrite(path, png)
  puts "#{style}: #{path} (#{png.bytesize} bytes, 1200x1500)"
end

raise "Source bytes changed" unless before == images.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) }
puts "Original dummy image SHA-256 values unchanged; no database or external API used."
