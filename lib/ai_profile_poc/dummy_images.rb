require "vips"

module AiProfilePoc
  # Original geometric stand-ins: no downloaded images, people, or AI calls.
  class DummyImages
    IDS = %w[photo-live photo-record photo-goods].freeze

    def self.build
      IDS.each_with_index.to_h do |id, index|
        xy = Vips::Image.xyz(900, 600)
        x, y = xy.bandsplit
        palettes = [ [ 30, 15, 65 ], [ 30, 70, 80 ], [ 150, 85, 70 ] ]
        canvas = Vips::Image.black(900, 600, bands: 3).new_from_image(palettes[index]).copy(interpretation: :srgb)
        5.times do |n|
          circle = ((x - (110 + n * 170)) ** 2 + (y - (100 + (n % 2) * 80)) ** 2) < (60 + index * 15) ** 2
          canvas = circle.ifthenelse([ 220 - index * 25, 120 + n * 20, 200 ], canvas)
        end
        if index == 0
          8.times do |n|
            canvas = canvas.draw_rect([ 100 + n * 20, 230, 210 ], 60 + n * 105, 390 - n % 3 * 25, 12, 190, fill: true)
          end
          canvas = canvas.draw_rect([ 245, 170, 220 ], 140, 255, 620, 32, fill: true)
        elsif index == 1
          disc = ((x - 450) ** 2 + (y - 340) ** 2) < 190 ** 2
          hole = ((x - 450) ** 2 + (y - 340) ** 2) < 50 ** 2
          canvas = disc.ifthenelse([ 22, 30, 42 ], canvas)
          canvas = hole.ifthenelse([ 240, 190, 130 ], canvas)
        else
          canvas = canvas.draw_rect([ 250, 230, 195 ], 170, 250, 260, 300, fill: true)
          canvas = canvas.draw_rect([ 170, 210, 185 ], 490, 300, 240, 220, fill: true)
          canvas = canvas.draw_rect([ 200, 125, 125 ], 220, 310, 160, 18, fill: true)
        end
        [ id, canvas.cast(:uchar).write_to_buffer(".png", strip: true) ]
      end
    end
  end
end
