require "digest"

class CardsController < ApplicationController
  LIFETIME = 15.minutes
  PURPOSE = "photo-card-download-v2"

  prepend_before_action :private_response

  def new
    return redirect_to(edit_profile_path, alert: "カードを作る前にプロフィールを保存してください。") unless current_user.profile

    @user_oshis = current_user.user_oshis.includes(:oshi, representative_image_attachment: :blob).order(:id)
  end

  def create
    settings = card_settings
    photo = Cards::Photo.new(user: current_user, **settings)
    fingerprint = photo.fingerprint
    png = photo.render
    raise SourceChanged unless Cards::Photo.new(user: current_user, **settings).fingerprint == fingerprint

    generated_at = Time.current
    payload = {
      "user_id" => current_user.id, "auth_context" => auth_context,
      "settings" => settings.stringify_keys, "source" => fingerprint,
      "png_sha256" => Digest::SHA256.hexdigest(png), "byte_size" => png.bytesize,
      "expires_at" => (generated_at + LIFETIME).to_i
    }
    response.headers["X-Card-Receipt"] = verifier.generate(payload, purpose: PURPOSE)
    response.headers["X-Card-Expires-At"] = payload["expires_at"].to_s
    response.headers["X-PNG-SHA256"] = payload["png_sha256"]
    send_data png, type: "image/png", disposition: "inline"
  rescue UnsupportedTemplate
    render_error("このテンプレートのPNG生成は未実装です。ビジュアル重視を選択してください。", :unprocessable_content)
  rescue Cards::Crop::Invalid
    render_error("画像の調整範囲が不正です。画像内の範囲と1.0〜3.0倍の倍率を指定してください。", :unprocessable_content)
  rescue ActionDispatch::Http::Parameters::ParseError
    render_error("画像の調整設定を正しいJSON形式で指定してください。", :bad_request)
  rescue ActionController::BadRequest, ArgumentError
    render_error("推しを重複なく1〜4人、正しい形式で選択してください。", :unprocessable_content)
  rescue ActiveRecord::RecordNotFound
    render_error("選択した推しは利用できません。", :not_found)
  rescue Cards::Photo::ProfileRequired
    render_error("プロフィールを保存してから作成してください。", :unprocessable_content)
  rescue Cards::Photo::InvalidImage
    render_error("登録画像を読み取れません。未登録とは異なる状態です。画像を確認してください。", :unprocessable_content)
  rescue Cards::Photo::FontUnavailable
    render_error("描画用フォントを利用できません。", :service_unavailable)
  rescue SourceChanged
    render_error("元データが変更されました。もう一度プレビューを作成してください。", :conflict)
  end

  def download
    receipt = request.headers["X-Card-Receipt"].to_s
    return render_error("保存情報が不正です。", :unprocessable_content) if receipt.bytesize > 16.kilobytes
    payload = verifier.verified(receipt, purpose: PURPOSE)
    return render_error("保存情報が不正です。再生成してください。", :unprocessable_content) unless payload
    return render_error("この画像は保存できません。", :forbidden) unless payload["user_id"] == current_user.id && payload["auth_context"] == auth_context
    return render_error("プレビューの期限が切れました。再生成してください。", :gone) if Time.current.to_i >= payload["expires_at"]
    return render_error("画像のサイズが一致しません。", :unprocessable_content) unless request.content_length == payload["byte_size"]

    png = request.raw_post
    return render_error("確認した画像と一致しません。", :unprocessable_content) unless Digest::SHA256.hexdigest(png) == payload["png_sha256"]
    settings = payload["settings"].symbolize_keys
    raise SourceChanged unless Cards::Photo.new(user: current_user, **settings).fingerprint == payload["source"]

    response.headers["X-PNG-SHA256"] = payload["png_sha256"]
    send_data png, type: "image/png", disposition: "attachment", filename: "oshilog-card.png"
  rescue ActiveRecord::RecordNotFound, Cards::Photo::ProfileRequired, Cards::Photo::InvalidImage, SourceChanged
    render_error("元データまたは画像が変更されたか、取得できません。再生成してください。", :conflict)
  end

  private
    class SourceChanged < StandardError; end
    class UnsupportedTemplate < StandardError; end

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Vary"] = "Cookie"
      response.headers["X-Content-Type-Options"] = "nosniff"
      render_error("ログインしてください。", :unauthorized) if action_name != "new" && !user_signed_in?
    end

    def card_settings
      input = params.require(:card)
      raise ActionController::BadRequest unless input.is_a?(ActionController::Parameters)
      raise UnsupportedTemplate if input.key?(:template) && input[:template] != "photo"
      ids = input[:user_oshi_ids]
      raise ArgumentError unless ids.is_a?(Array) && ids.length.between?(1, 4) && ids.uniq.length == ids.length
      raise ArgumentError unless ids.all? { |id| id.is_a?(String) && id.match?(/\A[1-9][0-9]{0,18}\z/) && id.to_i <= 2**63 - 1 }
      images = input[:image_user_oshi_ids]
      raise ArgumentError unless images.is_a?(Array) && images.length == ids.length
      # Rails removes null entries from parameter arrays. An empty string keeps
      # disabled frames in place instead of shifting the following image source.
      raise ArgumentError unless images.all? { |id| id == "" || ids.include?(id) }
      raise ArgumentError unless [ true, false ].include?(input[:show_introduction])
      settings = { user_oshi_ids: ids, image_user_oshi_ids: images, show_introduction: input[:show_introduction] }
      if input.key?(:crops)
        crops = input[:crops]
        raise Cards::Crop::Invalid unless crops.is_a?(Array) && crops.length == ids.length

        settings[:crops] = crops.map do |crop|
          raise Cards::Crop::Invalid unless crop.is_a?(ActionController::Parameters)

          Cards::Crop.normalize(crop.to_unsafe_h)
        end
      end
      settings
    end

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def auth_context
      Digest::SHA256.hexdigest(request.session.id.to_s)
    end

    def render_error(message, status)
      render json: { error: message }, status: status
    end
end
