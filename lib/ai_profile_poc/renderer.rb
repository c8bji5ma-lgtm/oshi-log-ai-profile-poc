require "cgi"
require "vips"
require_relative "layout"

module AiProfilePoc
  class Renderer
    FONT_FILE = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"

    def initialize(layout:, images:)
      @layout = layout
      @images = images
    end

    def render
      @layout.validate!
      raise Layout::Invalid, "Japanese font unavailable" unless File.file?(FONT_FILE)

      proposal = @layout.proposal
      canvas = solid(Layout::WIDTH, Layout::HEIGHT, proposal.fetch("background"))
      proposal.fetch("elements").each do |element|
        layer = case element.fetch("type")
        when "rect" then solid(element["width"], element["height"], element["color"])
        when "image" then picture(element)
        when "text" then text(element)
        end
        canvas = canvas.composite(layer, :over, x: element["x"], y: element["y"])
      end
      canvas.flatten.write_to_buffer(".png", compression: 6, strip: true)
    rescue Vips::Error, KeyError => error
      raise Layout::Invalid, error.message
    end

    private
      def rgb(color)
        color.delete_prefix("#").scan(/../).map { |part| part.to_i(16) }
      end

      def solid(width, height, color)
        Vips::Image.black(width, height, bands: 3).new_from_image(rgb(color)).copy(interpretation: :srgb)
      end

      def picture(element)
        # Only bytes supplied by the caller are decoded; JSON cannot name a path/URL.
        source = Vips::Image.new_from_buffer(@images.fetch(element["image_id"]), "", fail_on: :error).autorot.colourspace(:srgb)
        width, height = element.values_at("width", "height")
        crop = element.fetch("crop")
        scale = [ width.to_f / source.width, height.to_f / source.height ].max * crop["zoom"]
        half_x = width / (2.0 * source.width * scale)
        half_y = height / (2.0 * source.height * scale)
        unless crop["x"].between?(half_x - 1e-9, 1 - half_x + 1e-9) && crop["y"].between?(half_y - 1e-9, 1 - half_y + 1e-9)
          raise Layout::Invalid, "crop outside source image"
        end
        resized = source.resize(scale)
        left = (crop["x"] * resized.width - width / 2.0).floor.clamp(0, resized.width - width)
        top = (crop["y"] * resized.height - height / 2.0).floor.clamp(0, resized.height - height)
        resized.crop(left, top, width, height)
      end

      def glyph(value, size)
        Vips::Image.text(CGI.escapeHTML(value), font: "Noto Sans CJK JP #{size}", fontfile: FONT_FILE, dpi: 72)
      end

      def text(element)
        value = @layout.activity(element["activity_id"]).fetch(element["field"])
        value = value.join(" / ") if value.is_a?(Array)
        width, height, size = element.values_at("width", "height", "size")
        clusters = value.each_grapheme_cluster.to_a
        # One line for this PoC. Long registered values end with an ellipsis.
        if glyph(value, size).width > width
          clusters.pop while clusters.any? && glyph(clusters.join + "…", size).width > width
          value = clusters.join + "…"
        end
        mask = glyph(value, size)
        raise Layout::Invalid, "text box too small" if mask.width > width || mask.height > height

        ink = mask.new_from_image(rgb(element["color"])).bandjoin(mask).copy(interpretation: :srgb)
        ink.embed(0, 0, width, height, extend: :background, background: [ 0, 0, 0, 0 ])
      end
  end
end
