require "spec_helper"
require "digest"
require_relative "../../lib/ai_profile_poc/layout"
require_relative "../../lib/ai_profile_poc/renderer"
require_relative "../../lib/ai_profile_poc/dummy_images"

RSpec.describe "Issue #68 offline layout PoC" do
  let(:fixtures) { File.expand_path("../../docs/ai_profile_poc", __dir__) }
  let(:data) { JSON.parse(File.read(File.join(fixtures, "activities.json"))) }
  let(:proposal) { JSON.parse(File.read(File.join(fixtures, "mocks/live.json"))) }
  let(:images) { AiProfilePoc::DummyImages.build }

  def layout(value = proposal, owner_id: data.fetch("owner_id"), image_ids: AiProfilePoc::DummyImages::IDS)
    AiProfilePoc::Layout.new(json: JSON.generate(value), owner_id: owner_id,
      activities: data.fetch("activities"), image_ids: image_ids)
  end

  def render(value = proposal)
    AiProfilePoc::Renderer.new(layout: layout(value), images: images).render
  end

  def image_element
    proposal.fetch("elements").find { |element| element["type"] == "image" }
  end

  def text_element
    proposal.fetch("elements").find { |element| element["type"] == "text" }
  end

  it "accepts each mock through the same contract" do
    AiProfilePoc::Layout::STYLES.each do |style|
      value = JSON.parse(File.read(File.join(fixtures, "mocks/#{style}.json")))
      expect(layout(value).proposal["style"]).to eq(style)
    end
  end

  [ nil, [], "bad", 1 ].each do |value|
    it "rejects a non-object root #{value.inspect}" do
      expect { layout(value) }.to raise_error(AiProfilePoc::Layout::Invalid)
    end
  end

  it "rejects malformed, oversized and deeply nested JSON before rendering" do
    [ "{", " " * (AiProfilePoc::Layout::MAX_BYTES + 1), "[" * 20 + "0" + "]" * 20 ].each do |json|
      expect do
        AiProfilePoc::Layout.new(json: json, owner_id: "fictional-user", activities: [], image_ids: [])
      end.to raise_error(AiProfilePoc::Layout::Invalid)
    end
  end

  {
    "version" => [ 2, 1.0, "1" ], "style" => [ "arbitrary", nil ],
    "background" => [ "red", "#FFF", "url(file:///etc/passwd)" ],
    "elements" => [ [], nil, [ nil ] ]
  }.each do |key, values|
    values.each do |value|
      it "rejects invalid #{key}: #{value.inspect}" do
        proposal[key] = value
        expect { layout }.to raise_error(AiProfilePoc::Layout::Invalid)
      end
    end
  end

  it "rejects unknown keys, missing keys and more than 32 elements or 6 photos" do
    extra = proposal.merge("html" => "<script>bad</script>")
    missing = proposal.reject { |key, _| key == "style" }
    too_many = proposal.merge("elements" => proposal["elements"] * 3)
    too_many_images = proposal.merge("elements" => [ image_element ] * 7)
    [ extra, missing, too_many, too_many_images ].each do |value|
      expect { layout(value) }.to raise_error(AiProfilePoc::Layout::Invalid)
    end
  end

  {
    "x" => [ -1, 1200, 0.5, "72" ], "y" => [ -1, 1500 ],
    "width" => [ 0, 63, 1201 ], "height" => [ 0, 63, 1501 ],
    "type" => [ "svg", "html", "url" ],
    "activity_id" => [ "another-users-activity" ],
    "image_id" => [ "photo-record", "https://example.com/photo.png", "../../etc/passwd" ]
  }.each do |key, values|
    values.each do |value|
      it "rejects invalid image #{key}: #{value.inspect}" do
        image_element[key] = value
        expect { layout }.to raise_error(AiProfilePoc::Layout::Invalid)
      end
    end
  end

  it "rejects a box whose right or bottom edge leaves the canvas" do
    image_element["x"] = 200
    expect { layout }.to raise_error(AiProfilePoc::Layout::Invalid)
    image_element["x"] = 72
    image_element["y"] = 1000
    expect { layout }.to raise_error(AiProfilePoc::Layout::Invalid)
  end

  it "rejects an image excluded from the caller's allowed list" do
    expect { layout(image_ids: %w[photo-record photo-goods]) }.to raise_error(AiProfilePoc::Layout::Invalid)
  end

  it "rejects an activity belonging to another owner and ambiguous activity IDs" do
    expect { layout(owner_id: "someone-else") }.to raise_error(AiProfilePoc::Layout::Invalid)
    data["activities"] << data["activities"].first.dup
    expect { layout }.to raise_error(AiProfilePoc::Layout::Invalid)
  end

  {
    "title" => [ nil, "", "x" * 256, "bad\u0000text" ],
    "occurred_on" => [ nil, "2026-02-30", "2026-9-1" ],
    "oshi_names" => [ [], [ "" ], [ "x" * 51 ], [ "name" ] * 5 ]
  }.each do |key, values|
    values.each do |value|
      it "rejects missing or invalid source #{key}: #{value.inspect}" do
        data["activities"].first[key] = value
        expect { layout }.to raise_error(AiProfilePoc::Layout::Invalid)
      end
    end
  end

  it "rejects injected text, arbitrary fields, fonts and invalid text sizes" do
    [ [ "value", "invented biography" ], [ "field", "memo" ], [ "font", "/etc/passwd" ],
      [ "size", 65 ], [ "size", 15 ], [ "color", "#GG0000" ], [ "height", 8 ] ].each do |key, value|
      edited = Marshal.load(Marshal.dump(proposal))
      edited["elements"].find { |element| element["type"] == "text" }[key] = value
      expect { layout(edited) }.to raise_error(AiProfilePoc::Layout::Invalid)
    end
  end

  it "rejects invalid crop ranges, types and keys" do
    [ { "x" => -0.1, "y" => 0.5, "zoom" => 1 },
      { "x" => 0.5, "y" => 1.1, "zoom" => 1 },
      { "x" => "0.5", "y" => 0.5, "zoom" => 1 },
      { "x" => 0.5, "y" => 0.5, "zoom" => 3.1 },
      { "x" => 0.5, "y" => 0.5, "zoom" => 0.9 }, {} ].each do |crop|
      image_element["crop"] = crop
      expect { layout }.to raise_error(AiProfilePoc::Layout::Invalid)
    end
  end

  it "renders distinct 1200x1500 PNGs for all three mocks and preserves source bytes" do
    originals = images.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) }
    outputs = AiProfilePoc::Layout::STYLES.map do |style|
      value = JSON.parse(File.read(File.join(fixtures, "mocks/#{style}.json")))
      bytes = render(value)
      expect(bytes).to start_with("\x89PNG\r\n\x1a\n".b)
      png = Vips::Image.new_from_buffer(bytes, "")
      expect([ png.width, png.height, png.bands ]).to eq([ 1200, 1500, 3 ])
      expect(png.getpoint(1199, 1499)).to eq(value["background"].delete_prefix("#").scan(/../).map { |hex| hex.to_i(16) })
      Digest::SHA256.hexdigest(bytes)
    end
    expect(outputs.uniq.length).to eq(3)
    expect(images.transform_values { |bytes| Digest::SHA256.hexdigest(bytes) }).to eq(originals)
  end

  it "composites the exact resized and cropped pixels of the original dummy image" do
    png = Vips::Image.new_from_buffer(render, "")
    source = Vips::Image.new_from_buffer(images.fetch("photo-live"), "")
    resized = source.resize(1056.0 / 900)
    expected = resized.crop(0, ((resized.height - 570) / 2.0).floor, 1056, 570)
    actual = png.crop(72, 170, 1056, 570)
    expect((actual - expected).abs.max).to eq(0)
  end

  it "rejects an out-of-source crop and invalid or unavailable source bytes" do
    image_element["crop"]["x"] = 0
    expect { render }.to raise_error(AiProfilePoc::Layout::Invalid, /crop/)
    image_element["crop"]["x"] = 0.5
    images["photo-live"] = "not a PNG"
    expect { render }.to raise_error(AiProfilePoc::Layout::Invalid)
    images.delete("photo-live")
    expect { render }.to raise_error(AiProfilePoc::Layout::Invalid)
  end

  it "revalidates a proposal if changed after construction" do
    validated = layout
    validated.proposal["elements"].first["type"] = "svg"
    expect { AiProfilePoc::Renderer.new(layout: validated, images: {}).render }.to raise_error(AiProfilePoc::Layout::Invalid)
  end

  it "escapes markup and truncates long registered text within its box" do
    data["activities"].first["title"] = '<span foreground="red">架空 & 記録</span>' + "長いタイトル" * 25
    text_element["field"] = "title"
    expect { render }.not_to raise_error
    text_element["width"] = 1
    expect { render }.to raise_error(AiProfilePoc::Layout::Invalid, /text box/)
  end
end
