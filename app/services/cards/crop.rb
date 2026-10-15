module Cards
  # Coordinates refer to the centre of the visible window in the autorotated image.
  # Keep the formula in sync with app/javascript/lib/crop_geometry.js.
  class Crop
    DEFAULT = { "x" => 0.5, "y" => 0.5, "zoom" => 1.0 }.freeze
    EPSILON = 1e-9
    class Invalid < StandardError; end

    def self.normalize(value)
      raise Invalid unless value.is_a?(Hash) && value.keys.map(&:to_s).sort == %w[x y zoom]

      value = value.stringify_keys
      raise Invalid unless value.values.all? { |number| (number.is_a?(Integer) || number.is_a?(Float)) && number.finite? }
      raise Invalid unless value["x"].between?(0, 1) && value["y"].between?(0, 1) && value["zoom"].between?(1, 3)

      value.transform_values(&:to_f)
    end

    def self.geometry(image_width:, image_height:, width:, height:, crop:)
      crop = normalize(crop)
      scale = [ width.to_f / image_width, height.to_f / image_height ].max * crop.fetch("zoom")
      half_x = width / (2.0 * image_width * scale)
      half_y = height / (2.0 * image_height * scale)
      raise Invalid unless crop["x"].between?(half_x - EPSILON, 1 - half_x + EPSILON) &&
        crop["y"].between?(half_y - EPSILON, 1 - half_y + EPSILON)

      resized_width = (image_width * scale).round
      resized_height = (image_height * scale).round
      # A floating-point boundary may differ by a fraction of a pixel. Clamp only
      # after the normalized window has passed the bounds check above.
      left = (crop["x"] * resized_width - width / 2.0).floor.clamp(0, resized_width - width)
      top = (crop["y"] * resized_height - height / 2.0).floor.clamp(0, resized_height - height)
      { scale: scale, left: left, top: top }
    end
  end
end
