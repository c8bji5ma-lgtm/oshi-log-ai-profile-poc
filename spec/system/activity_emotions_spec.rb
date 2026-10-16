require "rails_helper"

RSpec.describe "Activity emotion selection", type: :system do
  it "registers, edits and clears multiple tags through the activity form" do
    user = create(:user)
    registration = create(:user_oshi, user: user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button "Log in"
    expect(page).to have_css("main h1", text: "ホーム", exact_text: true)

    visit new_activity_path
    select registration.oshi.name, from: "推し（必須・1件以上）"
    fill_in "活動日（必須）", with: Date.current
    select "ライブ・イベント", from: "カテゴリ（必須）"
    fill_in "タイトル（必須）", with: "感情タグの記録"
    select "嬉しい", from: "感情タグ（任意・複数選択可）"
    select "感動", from: "感情タグ（任意・複数選択可）"
    click_button "記録する"
    expect(page).to have_css(".activity-list .activity-emotions", text: "嬉しい、感動", exact_text: true)
    click_link "感情タグの記録"
    expect(page).to have_css("dd.activity-emotions", text: "嬉しい、感動", exact_text: true)
    click_link "編集", exact: true
    expect(page).to have_select("感情タグ（任意・複数選択可）", selected: [ "嬉しい", "感動" ])
    unselect "嬉しい", from: "感情タグ（任意・複数選択可）"
    select "幸せ", from: "感情タグ（任意・複数選択可）"
    click_button "更新する"
    expect(page).to have_css("dd.activity-emotions", text: "感動、幸せ", exact_text: true)

    click_link "編集", exact: true
    unselect "感動", from: "感情タグ（任意・複数選択可）"
    unselect "幸せ", from: "感情タグ（任意・複数選択可）"
    click_button "更新する"
    expect(page).to have_css("dd.activity-emotions", text: "—", exact_text: true)
    expect(user.activities.sole.emotions).to be_empty
  end
end
