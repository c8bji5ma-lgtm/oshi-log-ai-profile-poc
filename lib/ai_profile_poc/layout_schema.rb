require_relative "layout"

module AiProfilePoc
  # Shared wire schema. Layout remains authoritative for semantic constraints.
  class LayoutSchema
    def self.build
      integer = ->(min, max) { { "type" => "integer", "minimum" => min, "maximum" => max } }
      color = { "type" => "string", "description" => "A six-digit #RRGGBB hex color" }
      common = { "x" => integer.call(0, Layout::WIDTH - 1), "y" => integer.call(0, Layout::HEIGHT - 1),
        "width" => integer.call(1, Layout::WIDTH), "height" => integer.call(1, Layout::HEIGHT) }
      reference = { "activity_id" => { "type" => "string" } }
      crop = object(%w[x y zoom].to_h do |key|
        [ key, { "type" => "number", "minimum" => key == "zoom" ? 1 : 0, "maximum" => key == "zoom" ? 3 : 1 } ]
      end)
      variants = {
        "rect" => { "color" => color },
        "image" => reference.merge("image_id" => { "type" => "string" }, "crop" => crop),
        "text" => reference.merge("field" => { "type" => "string", "enum" => Layout::FIELDS },
          "size" => integer.call(16, 64), "color" => color)
      }.map do |type, properties|
        object(common.merge("type" => { "type" => "string", "enum" => [ type ] }).merge(properties))
      end
      object("version" => { "type" => "integer", "enum" => [ 1 ] },
        "style" => { "type" => "string", "enum" => Layout::STYLES }, "background" => color,
        "elements" => { "type" => "array", "minItems" => 1, "maxItems" => 32, "items" => { "anyOf" => variants } })
    end

    def self.object(properties)
      { "type" => "object", "properties" => properties, "required" => properties.keys, "additionalProperties" => false }
    end
    private_class_method :object
  end
end
