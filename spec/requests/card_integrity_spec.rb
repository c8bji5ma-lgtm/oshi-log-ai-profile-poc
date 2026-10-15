require "rails_helper"

RSpec.describe "Card download integrity across templates", type: :request do
  %w[photo memory data].each do |template|
    it "separately rejects size and SHA-256 mismatches for #{template} without changing the preview" do
      user = create(:user)
      create(:profile, user: user)
      post user_session_path, params: { user: { email: user.email, password: "password123" } }
      settings = case template
      when "photo"
        registration = create(:user_oshi, user: user)
        { user_oshi_ids: [ registration.id.to_s ], image_user_oshi_ids: [ "" ], show_introduction: true }
      when "memory"
        activity = create(:activity, user: user, occurred_on: Date.current)
        { activity_ids: [ activity.id.to_s ], image_attachment_ids: [ "" ], crops: [ Cards::Crop::DEFAULT ] }
      else
        { year: Date.current.year.to_s, oshi_id: "" }
      end
      post card_path, params: { card: settings.merge(template: template) }, as: :json
      expect(response).to have_http_status(:ok)
      png = response.body.dup
      receipt = response.headers.fetch("X-Card-Receipt")
      expect(receipt.bytesize).to be <= 16.kilobytes
      expect(response.headers.fetch("X-PNG-SHA256")).to eq(Digest::SHA256.hexdigest(png))
      headers = { "CONTENT_TYPE" => "image/png", "X-Card-Receipt" => receipt }

      modified = png.dup
      modified.setbyte(modified.bytesize - 1, modified.getbyte(modified.bytesize - 1) ^ 1)
      expect(modified.bytesize).to eq(png.bytesize)
      post download_card_path, params: modified, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.fetch("error")).to eq("確認した画像と一致しません。")

      post download_card_path, params: png + "changed", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.fetch("error")).to eq("画像のサイズが一致しません。")

      post download_card_path, params: png, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(png)
      expect(response.headers.fetch("X-PNG-SHA256")).to eq(Digest::SHA256.hexdigest(png))
    end
  end
end
