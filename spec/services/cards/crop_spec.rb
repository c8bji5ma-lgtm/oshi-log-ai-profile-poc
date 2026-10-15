require "rails_helper"

RSpec.describe Cards::Crop do
  def geometry(crop, image_width: 900, image_height: 600, width: 496, height: 620)
    described_class.geometry(image_width: image_width, image_height: image_height, width: width, height: height, crop: crop)
  end

  it "calculates the legacy central cover window at zoom one" do
    result = geometry(described_class::DEFAULT)
    expect(result[:scale]).to be_within(1e-12).of(620.0 / 600)
    expect(result.values_at(:left, :top)).to eq([ 217, 0 ])
  end

  it "calculates a translated three-times window" do
    result = geometry({ "x" => 0.25, "y" => 0.35, "zoom" => 3 })
    expect(result[:scale]).to be_within(1e-12).of(3.1)
    expect(result.values_at(:left, :top)).to eq([ 449, 341 ])
  end

  [ [ 900, 600 ], [ 600, 900 ], [ 997, 613 ], [ 1, 1 ] ].each do |iw, ih|
    [ [ 496, 620 ], [ 416, 520 ], [ 352, 440 ] ].each do |width, height|
      it "stays inside #{iw}x#{ih} at the maximum legal edge for a #{width}x#{height} frame" do
        scale = [ width.to_f / iw, height.to_f / ih ].max * 3
        crop = { x: 1 - width / (2.0 * iw * scale), y: height / (2.0 * ih * scale), zoom: 3 }
        result = geometry(crop, image_width: iw, image_height: ih, width: width, height: height)
        expect(result[:left]).to be_between(0, (iw * scale).round - width)
        expect(result[:top]).to be_between(0, (ih * scale).round - height)
      end
    end
  end

  it "rejects a normalized centre that would expose the image exterior" do
    expect { geometry({ x: 0.1, y: 0.5, zoom: 1 }) }.to raise_error(described_class::Invalid)
    expect { geometry({ x: 0.5, y: 0.49, zoom: 1 }) }.to raise_error(described_class::Invalid)
  end

  [ Float::NAN, Float::INFINITY, -Float::INFINITY, -1, "0.5", true, nil ].each do |number|
    it "rejects non-finite, negative or non-numeric coordinates #{number.inspect}" do
      expect { geometry({ x: number, y: 0.5, zoom: 1 }) }.to raise_error(described_class::Invalid)
    end
  end
end
