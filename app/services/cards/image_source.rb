require "digest"
require "vips"

module Cards
  # Read and validate originals without writing blobs or attachment metadata.
  class ImageSource
    def self.read(blob)
      new.read(blob)
    end

    def read(blob)
      raise Photo::InvalidImage unless ImageAttachmentValidator::CONTENT_TYPES.include?(blob.content_type)
      raise Photo::InvalidImage unless blob.byte_size.positive? && blob.byte_size <= ImageAttachmentValidator::MAX_BYTE_SIZE

      bytes = blob.download
      raise Photo::InvalidImage unless bytes.bytesize == blob.byte_size && Digest::MD5.base64digest(bytes) == blob.checksum
      validate_format!(bytes, blob.content_type)
      image = Vips::Image.new_from_buffer(bytes, "", access: :sequential, fail_on: :error)
      raise Photo::InvalidImage unless image.width.positive? && image.height.positive?
      raise Photo::InvalidImage if image.get_typeof("n-pages").positive? && image.get("n-pages") != 1
      bytes
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError, Vips::Error, Errno::ENOENT
      raise Photo::InvalidImage
    end

    private
      def validate_format!(bytes, type)
        case type
        when "image/jpeg"
          raise Photo::InvalidImage unless bytes.start_with?("\xff\xd8\xff".b)
        when "image/png"
          raise Photo::InvalidImage unless bytes.start_with?(Photo::PNG_SIGNATURE)
          offset = 8
          while offset + 12 <= bytes.bytesize
            length = bytes.byteslice(offset, 4).unpack1("N")
            kind = bytes.byteslice(offset + 4, 4)
            raise Photo::InvalidImage if kind == "acTL" || offset + length + 12 > bytes.bytesize
            offset += length + 12
            break if kind == "IEND"
          end
        when "image/webp"
          raise Photo::InvalidImage unless bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP"
          offset = 12
          while offset + 8 <= bytes.bytesize
            kind = bytes.byteslice(offset, 4)
            length = bytes.byteslice(offset + 4, 4).unpack1("V")
            raise Photo::InvalidImage if %w[ANIM ANMF].include?(kind) || offset + length + 8 > bytes.bytesize
            offset += 8 + length + length % 2
          end
        end
      end
  end
end
