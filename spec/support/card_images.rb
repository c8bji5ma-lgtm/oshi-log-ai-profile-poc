module CardImages
  def coordinate_image(width: 900, height: 600, orientation: nil)
    coordinates = Vips::Image.xyz(width, height)
    red = coordinates[0].linear(255.0 / (width - 1), 0)
    green = coordinates[1].linear(255.0 / (height - 1), 0)
    image = red.bandjoin(green).bandjoin(red.new_from_image(80)).cast(:uchar).copy(interpretation: :srgb)
    if orientation
      image.set_type(GObject::GINT_TYPE, "orientation", orientation)
      image.write_to_buffer(".jpg", Q: 100)
    else
      image.write_to_buffer(".png")
    end
  end

  def attach_coordinates(record, **options)
    bytes = coordinate_image(**options)
    record.representative_image.attach(io: StringIO.new(bytes), filename: options[:orientation] ? "oriented.jpg" : "coordinates.png")
    bytes
  end
end
