require "rails_helper"

RSpec.describe "Admin oshi moderation", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let(:oshi) { create(:oshi, created_by_user: user) }

  def sign_in_as(account)
    post user_session_path, params: { user: { email: account.email, password: "password123" } }
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def moderation_path(action, record)
    public_send("#{action}_admin_oshi_path", record)
  end

  context "when signed out" do
    it "requires login to view the pending list" do
      get admin_oshis_path
      expect(response).to redirect_to(new_user_session_path)
    end

    [ :approve, :reject ].each do |action|
      it "requires login to #{action} an oshi" do
        patch moderation_path(action, oshi)
        expect(response).to redirect_to(new_user_session_path)
        expect(oshi.reload).to be_pending
      end
    end
  end

  context "when signed in as a regular user" do
    before { sign_in_as(user) }

    it "refuses access to the pending list" do
      oshi
      get admin_oshis_path
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("管理者権限が必要です。")
      expect(response.body).not_to include(oshi.name)
    end

    [ :approve, :reject ].each do |action|
      it "refuses to #{action} even the user's own pending oshi" do
        patch moderation_path(action, oshi)
        expect(response).to have_http_status(:forbidden)
        expect(oshi.reload).to be_pending
      end
    end

    it "does not show the management link on my page" do
      get my_page_path
      expect(document.at_css("a[href='#{admin_oshis_path}']")).to be_nil
    end
  end

  context "when signed in as an admin" do
    before { sign_in_as(admin) }

    it "lists all pending oshis with moderation buttons and excludes other statuses" do
      oshi
      own = create(:oshi, created_by_user: admin, affiliation: "所属表示")
      unowned = create(:oshi, created_by_user: nil)
      approved = create(:oshi, :approved)
      rejected = create(:oshi, :rejected)
      get admin_oshis_path
      expect(response).to have_http_status(:ok)
      expect(document.at_css("main h1").text).to eq("推し承認管理")
      expect(document.css("main h2").map(&:text)).to contain_exactly(oshi.name, own.name, unowned.name)
      expect(document.at_css("main").text).to include("アイドル", "所属表示", "未設定")
      expect(document.at_css("main").text).not_to include(approved.name, rejected.name)
      [ oshi, own, unowned ].each do |record|
        [ :approve, :reject ].each do |action|
          form = document.at_css("form[action='#{moderation_path(action, record)}']")
          expect(form["method"]).to eq("post")
          expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
          label = action == :approve ? "承認" : "却下"
          expect(form.at_css("button").text).to eq(label)
          expect(form.at_css("button")["aria-label"]).to eq("#{record.name}を#{label}")
        end
      end
    end

    it "shows an empty state when there are no pending oshis" do
      create(:oshi, :approved)
      get admin_oshis_path
      expect(response).to have_http_status(:ok)
      expect(document.at_css("main").text).to include("承認待ちの推しはありません。")
      expect(document.css("main form")).to be_empty
    end

    it "links to management from my page" do
      get my_page_path
      expect(document.at_css("a[href='#{admin_oshis_path}']").text).to eq("推し承認管理")
    end

    { approve: "approved", reject: "rejected" }.each do |action, status|
      it "changes only the status to #{status} and returns with a success notice" do
        original = oshi.attributes.except("status", "updated_at")
        patch moderation_path(action, oshi), params: { oshi: { status: "pending", name: "改ざん", created_by_user_id: admin.id } }
        expect(oshi.reload.status).to eq(status)
        expect(oshi.attributes.except("status", "updated_at")).to eq(original)
        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(admin_oshis_path)
        follow_redirect!
        label = action == :approve ? "承認" : "却下"
        expect(document.at_css("[role='status']").text).to eq("推しを#{label}しました。")
        expect(document.css("main h2").map(&:text)).not_to include(oshi.name)
      end

      [ :approved, :rejected ].each do |initial_status|
        it "refuses #{action} for an already #{initial_status} oshi" do
          record = create(:oshi, initial_status)
          original = record.attributes
          patch moderation_path(action, record)
          expect(record.reload.attributes).to eq(original)
          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(admin_oshis_path)
          follow_redirect!
          expect(document.at_css("[role='alert']").text).to include("承認待ちの推しのみ変更できます")
        end
      end

      it "retains pending status and reports a validation failure during #{action}" do
        oshi.update_column(:oshi_type, "未対応の種別")
        original = oshi.reload.attributes
        patch moderation_path(action, oshi)
        expect(oshi.reload.attributes).to eq(original)
        expect(response).to redirect_to(admin_oshis_path)
        follow_redirect!
        expect(document.at_css("[role='alert']").text).to include("推しを更新できませんでした")
      end

      it "reports a missing oshi during #{action} and returns to management" do
        missing_id = Oshi.maximum(:id).to_i + 1
        patch moderation_path(action, missing_id)
        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(admin_oshis_path)
        follow_redirect!
        expect(document.at_css("[role='alert']").text).to include("対象の推しが見つかりません")
      end
    end

    it "refuses a second decision after the pending list has been displayed" do
      oshi
      get admin_oshis_path
      patch approve_admin_oshi_path(oshi)
      patch reject_admin_oshi_path(oshi)
      expect(oshi.reload).to be_approved
      follow_redirect!
      expect(document.at_css("[role='alert']").text).to include("承認待ちの推しのみ変更できます")
    end

    it "preserves personal records after rejection while removing the oshi from search" do
      personal = create(:user_oshi, user: user, oshi: oshi, started_period: "2023/05")
      patch reject_admin_oshi_path(oshi)
      delete destroy_user_session_path
      sign_in_as(user)
      get new_oshi_path, params: { q: oshi.name }
      expect(document.at_css("option[value='#{oshi.id}']")).to be_nil
      [ user_oshi_path(personal), edit_user_oshi_path(personal) ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(document.at_css("main").text).to include(oshi.name)
      end
      patch user_oshi_path(personal), params: { user_oshi: { started_period: "2020", ended_period: "2024/05" } }
      expect(response).to redirect_to(oshis_path)
      expect(personal.reload).to have_attributes(started_period: "2020", ended_period: "2024/05")
      expect(oshi.reload).to be_rejected
    end
  end
end
