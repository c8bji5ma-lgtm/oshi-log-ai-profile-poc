require "json"
require "date"

module AiProfilePoc
  # Experimental contract, independent of Cards and persisted application data.
  class Layout
    WIDTH = 1200
    HEIGHT = 1500
    STYLES = %w[live magazine scrapbook].freeze
    FIELDS = %w[title occurred_on oshi_names].freeze
    MAX_BYTES = 65_536

    class Invalid < StandardError; end

    attr_reader :proposal

    def initialize(json:, owner_id:, activities:, image_ids:)
      check(json.is_a?(String) && json.bytesize <= MAX_BYTES, "JSON must be at most 64 KiB")
      @proposal = JSON.parse(json, max_nesting: 12)
      @owner_id = owner_id
      @activities = activities
      @image_ids = image_ids
      validate!
    rescue JSON::ParserError, JSON::NestingError => error
      raise Invalid, error.message
    end

    def validate!
      object!(proposal, %w[version style background elements])
      check(proposal["version"] == 1 && proposal["version"].is_a?(Integer), "unsupported version")
      check(STYLES.include?(proposal["style"]), "unsupported style")
      color!(proposal["background"])
      elements = proposal["elements"]
      check(elements.is_a?(Array) && elements.length.between?(1, 32), "expected 1..32 elements")
      check(elements.count { |element| element.is_a?(Hash) && element["type"] == "image" }.between?(1, 6), "expected 1..6 images")
      elements.each { |element| validate_element!(element) }
      self
    end

    def activity(id)
      matches = @activities.select { |record| record["id"] == id }
      check(id.is_a?(String) && matches.length == 1, "unknown or ambiguous activity")
      record = matches.first
      check(@owner_id.is_a?(String) && !@owner_id.empty? && record["owner_id"] == @owner_id, "activity owner mismatch")
      check(text?(record["title"], 255), "missing or invalid activity title")
      check(record["occurred_on"].is_a?(String) && record["occurred_on"].match?(/\A\d{4}-\d{2}-\d{2}\z/), "invalid activity date")
      begin
        Date.iso8601(record["occurred_on"])
      rescue Date::Error
        raise Invalid, "invalid activity date"
      end
      names = record["oshi_names"]
      check(names.is_a?(Array) && names.length.between?(1, 4) && names.all? { |name| text?(name, 50) }, "missing or invalid oshi names")
      record
    end

    private
      def validate_element!(element)
        check(element.is_a?(Hash), "element must be an object")
        common = %w[type x y width height]
        case element["type"]
        when "rect"
          object!(element, common + %w[color])
          color!(element["color"])
        when "image"
          object!(element, common + %w[activity_id image_id crop])
          record = activity(element["activity_id"])
          id = element["image_id"]
          check(id.is_a?(String) && @image_ids.include?(id) && record.fetch("image_ids", []).include?(id), "image does not belong to selected activity")
          crop = element["crop"]
          object!(crop, %w[x y zoom])
          %w[x y].each { |key| number!(crop[key], 0, 1) }
          number!(crop["zoom"], 1, 3)
        when "text"
          object!(element, common + %w[activity_id field size color])
          activity(element["activity_id"])
          check(FIELDS.include?(element["field"]), "unsupported text field")
          integer!(element["size"], 16, 64)
          color!(element["color"])
        else
          raise Invalid, "unsupported element type"
        end
        integer!(element["x"], 0, WIDTH - 1)
        integer!(element["y"], 0, HEIGHT - 1)
        integer!(element["width"], 1, WIDTH)
        integer!(element["height"], 1, HEIGHT)
        check(element["x"] + element["width"] <= WIDTH && element["y"] + element["height"] <= HEIGHT, "element outside canvas")
        if element["type"] == "image"
          check(element["width"] >= 64 && element["height"] >= 64, "image too small")
        elsif element["type"] == "text"
          check(element["height"] >= element["size"] + 8, "text box too short")
        end
      end

      def object!(value, keys)
        check(value.is_a?(Hash) && value.keys.sort == keys.sort, "unexpected or missing keys: expected #{keys.join(', ')}")
      end

      def color!(value)
        check(value.is_a?(String) && value.match?(/\A#[0-9a-fA-F]{6}\z/), "expected #RRGGBB color")
      end

      def integer!(value, min, max)
        check(value.is_a?(Integer) && value.between?(min, max), "integer outside #{min}..#{max}")
      end

      def number!(value, min, max)
        check((value.is_a?(Integer) || value.is_a?(Float)) && value.finite? && value.between?(min, max), "number outside #{min}..#{max}")
      end

      def text?(value, limit)
        value.is_a?(String) && value.valid_encoding? && !value.strip.empty? && value.length <= limit && !value.match?(/[[:cntrl:]]/)
      end

      def check(condition, message)
        raise Invalid, message unless condition
      end
  end
end
