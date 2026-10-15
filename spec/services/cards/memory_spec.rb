require "rails_helper"
require "tmpdir"
require_relative "../../support/card_images"

RSpec.describe Cards::Memory do
  include CardImages
  let(:user) { create(:user) }
  let(:activity) { create(:activity, :multiple_oshis, user: user, occurred_on: Date.current) }
  let(:profile) { create(:profile, user: user, display_name: "思い出の持ち主") }

  around do |example|
    registry = ActiveStorage::Blob.services
    service = ActiveStorage::Blob.service
    Dir.mktmpdir("oshilog-memory-service-") do |directory|
      storage = ActiveStorage::Service::DiskService.new(root: directory)
      storage.name = "test"
      ActiveStorage::Blob.services = { "test" => storage }
      ActiveStorage::Blob.service = storage
      example.run
    ensure
      ActiveStorage::Blob.services = registry
      ActiveStorage::Blob.service = service
    end
  end

  before { profile }

  def renderer(records = [ activity ], **options)
    described_class.new(user: user, activity_ids: records.map { |record| record.id.to_s },
      image_attachment_ids: records.map { |record| record.images_attachments.order(:id).first&.id.to_s },
      crops: records.map { Cards::Crop::DEFAULT }, **options)
  end

  def attach_photo(record, colour: nil, **options)
    bytes = colour ? Vips::Image.black(40, 40, bands: 3).new_from_image(colour).copy(interpretation: :srgb).write_to_buffer(".png") : coordinate_image(**options)
    record.images.attach(io: StringIO.new(bytes), filename: options[:orientation] ? "original.jpg" : "original.png")
    bytes
  end

  [ [ 568 ], [ 320, 816 ], [ 72, 568, 1064 ] ].each do |xs|
    it "uses precisely the approved #{xs.length}-activity layout without dummy frames" do
      colours = [ [ 210, 40, 30 ], [ 30, 160, 60 ], [ 50, 70, 220 ] ]
      records = Array.new(xs.length) do |index|
        record = create(:activity, user: user, occurred_on: Date.current)
        attach_photo(record, colour: colours[index])
        record
      end
      png = renderer(records).render
      image = Vips::Image.new_from_buffer(png, "")
      expect([ image.width, image.height ]).to eq([ 1600, 1000 ])
      xs.each_with_index do |x, index|
        expect(image.getpoint(x, 194).take(3)).to eq([ 255, 253, 249 ])
        expect(image.getpoint(x + 20, 214).take(3)).to eq(colours[index])
        expect(image.getpoint(x + 443, 613).take(3)).to eq(colours[index])
        expect(image.getpoint(x + 444, 614).take(3)).to eq([ 255, 253, 249 ])
        expect(image.getpoint(x + 463, 873).take(3)).to eq([ 255, 253, 249 ])
        expect(image.getpoint(x + 464, 874).take(3)).to eq([ 251, 243, 230 ])
      end
      unused = { 1 => [ 72, 1064 ], 2 => [ 72, 1528 ], 3 => [] }.fetch(xs.length)
      unused.each do |x|
        expect(image.getpoint(x, 194).take(3)).to eq([ 251, 243, 230 ])
      end
    end
  end

  it "keeps selected order and makes the selected photo and order visible in PNG pixels" do
    attach_photo(activity, colour: [ 200, 30, 20 ])
    second = create(:activity, user: user, occurred_on: Date.current)
    attach_photo(second, colour: [ 20, 30, 200 ])
    image = Vips::Image.new_from_buffer(renderer([ activity, second ]).render, "")
    reversed = Vips::Image.new_from_buffer(renderer([ second, activity ]).render, "")
    expect(image.getpoint(340, 214).take(3)).to eq([ 200, 30, 20 ])
    expect(reversed.getpoint(340, 214).take(3)).to eq([ 20, 30, 200 ])
    attach_photo(activity, colour: [ 30, 200, 20 ])
    chosen = renderer([ activity ], image_attachment_ids: [ activity.images_attachments.order(:id).last.id.to_s ])
    expect(Vips::Image.new_from_buffer(chosen.render, "").getpoint(588, 214).take(3)).to eq([ 30, 200, 20 ])
  end

  it "matches explicit central cropping, zoom and position after EXIF correction and preserves source bytes" do
    bytes = attach_photo(activity, orientation: 6)
    blob = activity.images.first.blob
    metadata = blob.reload.attributes
    attachment = activity.images.first.reload.attributes
    source = Vips::Image.new_from_buffer(bytes, "").autorot.colourspace(:srgb)
    expect([ source.width, source.height ]).to eq([ 600, 900 ])
    central = Vips::Image.new_from_buffer(renderer.render, "").crop(588, 214, 424, 400)
    resized = source.resize(424.0 / 600)
    expected_central = resized.crop(0, (resized.height - 400) / 2, 424, 400)
    expect((central - expected_central).abs.max).to eq(0)
    crop = { x: 0.4, y: 0.6, zoom: 3 }
    actual = Vips::Image.new_from_buffer(renderer(crops: [ crop ]).render, "").crop(588, 214, 424, 400)
    expected = source.resize(2.12).crop(296, 944, 424, 400)
    expect((actual - expected).abs.max).to eq(0)
    expect((actual - central).abs.max).to be > 0
    expect(blob.download).to eq(bytes)
    expect(blob.reload.attributes).to eq(metadata)
    expect(activity.images.first.reload.attributes).to eq(attachment)
  end

  it "renders the required fields at the approved coordinates and excludes sensitive fields" do
    activity.update!(memo: "秘密のメモ", place: "秘密の場所", amount: 987654)
    profile.update!(introduction: "秘密の自己紹介")
    service = renderer
    calls = []
    allow(service).to receive(:text).and_wrap_original do |original, canvas, value, **options|
      calls << [ value, options ]
      original.call(canvas, value, **options)
    end
    image = Vips::Image.new_from_buffer(service.render, "")
    expected = [ [ profile.display_name, 72, 72, 56 ], [ activity.occurred_on.strftime("%Y.%m.%d"), 588, 633, 24 ],
      [ activity.title, 588, 678, 32 ], [ activity.activity_type, 588, 786, 23 ],
      [ activity.oshis.order(:id).pluck(:name).join("・"), 588, 828, 23 ], [ "OshiLog", 72, 924, 24 ] ]
    expect(calls.reject { |value, _| value == "写真なし" }.map { |value, opts| [ value, opts[:x], opts[:y], opts[:size] ] }).to eq(expected)
    expect(calls.map(&:first)).not_to include(activity.memo, activity.place, activity.amount.to_s, profile.introduction)
    expect(image.getpoint(588, 214).take(3)).to eq([ 235, 226, 214 ])
    png = service.render
    activity.update!(memo: "別のメモ", amount: 123, place: "別の場所")
    expect(renderer.render).to eq(png)
  end

  it "truncates titles by grapheme and actual width, with names in one line and no text outside their rectangles" do
    activity.update!(title: "W👩‍👩‍👧‍👦é" * 24)
    activity.oshis.each { |oshi| oshi.update!(name: "幅の長い推し👩‍👩‍👧‍👦" * 12) }
    original = activity.reload.title
    service = renderer
    glyphs = []
    allow(service).to receive(:glyph_image).and_wrap_original do |original_method, value, size|
      glyphs << [ value, size ]
      original_method.call(value, size)
    end
    png = service.render
    image = Vips::Image.new_from_buffer(png, "")
    expect(glyphs.select { |_, size| size == 32 }.map(&:first)).to include(a_string_ending_with("…"))
    expect(glyphs.select { |_, size| size == 23 }.map(&:first)).to include(a_string_ending_with("…"))
    rendered_title = glyphs.select { |_, size| size == 32 }.last(2).map(&:first).join
    expect(rendered_title.each_grapheme_cluster.count).to be <= 24
    expect(rendered_title).to match(/\A(?:W|👩‍👩‍👧‍👦|é)+…\z/)
    expect(activity.reload.title).to eq(original)
    # Regions immediately beyond the bounded title/name area remain blank paper.
    [ [ 1012, 678, 20, 88 ], [ 588, 766, 424, 18 ], [ 1012, 828, 20, 32 ], [ 588, 860, 424, 14 ] ].each do |x, y, width, height|
      region = image.crop(x, y, width, height)
      expect((region - region.new_from_image([ 255, 253, 249 ])).abs.max).to eq(0)
    end
    # Pango receives complete graphemes and escaped markup.
    activity.update!(title: "<b>é👩‍👩‍👧‍👦</b>")
    expect { renderer.render }.not_to raise_error
  end

  it "rejects NaN, infinity, invalid window bounds and attempts to crop an absent image" do
    [ Float::NAN, Float::INFINITY, -Float::INFINITY ].each do |number|
      expect { renderer(crops: [ { x: 0.5, y: 0.5, zoom: number } ]) }.to raise_error(Cards::Crop::Invalid)
    end
    expect { renderer(crops: [ { x: 0.5, y: 0.5, zoom: 2 } ]) }.to raise_error(Cards::Crop::Invalid)
    attach_photo(activity)
    expect { renderer(crops: [ { x: 0, y: 0.5, zoom: 1 } ]) }.to raise_error(Cards::Crop::Invalid)
  end
end
