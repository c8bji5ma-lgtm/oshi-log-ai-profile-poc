require "rails_helper"
require "tmpdir"
require_relative "../support/image_attachments"

RSpec.describe "Profiles and photo cards in the browser", type: :system do
  include ImageAttachments

  let(:user) { create(:user) }
  let(:user_oshi) { create(:user_oshi, user: user, oshi: create(:oshi, :approved, name: "カードの推しA")) }
  let(:fixture_image) { Rails.root.join("spec/fixtures/files/image.png") }

  around do |example|
    previous_registry = ActiveStorage::Blob.services
    previous_service = ActiveStorage::Blob.service
    previous_forgery_protection = ApplicationController.allow_forgery_protection
    # The real card controller reads csrf_meta_tags, which Rails omits when protection is disabled.
    ApplicationController.allow_forgery_protection = true
    Dir.mktmpdir("oshilog-profile-card-system-") do |directory|
      @download_directory = Pathname.new(directory).join("downloads")
      FileUtils.mkdir_p(@download_directory)
      storage = ActiveStorage::Service::DiskService.new(root: File.join(directory, "storage"))
      storage.name = "test"
      ActiveStorage::Blob.services = { "test" => storage }
      ActiveStorage::Blob.service = storage
      example.run
    ensure
      begin
        Capybara.reset_sessions!
      ensure
        begin
          @editor_driver&.quit
        ensure
          # Stop background browser downloads before removing the example's temporary files.
          @download_driver&.quit
        end
      end
    end
  ensure
    ActiveStorage::Blob.services = previous_registry
    ActiveStorage::Blob.service = previous_service
    ApplicationController.allow_forgery_protection = previous_forgery_protection
  end

  before do
    user_oshi
    @download_driver = page.driver
    # Scope Chrome's real download directory to this example, including when the driver is reused.
    @download_driver.browser.download_path = @download_directory.to_s
  end

  def sign_in
    visit new_user_session_path
    within("main form") do
      fill_in "user_email", with: user.email
      fill_in "user_password", with: "password123"
      click_button "Log in"
    end
    expect(page).to have_css("main h1", text: "ホーム", exact_text: true)
  end

  def open_my_page
    within("nav[aria-label='グローバルナビゲーション']") { click_link "マイページ" }
    expect(page).to have_css("main h1", text: "マイページ", exact_text: true)
  end

  def open_card
    open_my_page
    click_link "カードを作成"
    expect(page).to have_css("main h1", text: "推し活カード作成", exact_text: true)
    expect(page).to have_select("1. #{user_oshi.oshi.name}の画像", selected: "#{user_oshi.oshi.name}の代表画像")
  end

  def check_loaded_image(alt)
    expect(page).to have_css("img[alt='#{alt}']", wait: 10) { |image|
      image.evaluate_script("this.complete && this.naturalWidth > 0 && this.naturalHeight > 0")
    }
  end

  def generate_preview
    click_button "プレビューを作成"
    expect(page).to have_css("[role='status']", text: "完成プレビューを確認してから保存してください。", wait: 10)
    expect(page).to have_css("main h2", text: "完成プレビュー", exact_text: true)
    check_loaded_image("生成した推し活カード")
    expect(page).to have_css("img[data-photo-card-target='image'][src^='blob:']")
    expect(page).to have_button("PNGをダウンロード", disabled: false)
    expect(page).to have_css("[data-photo-card-target='error']", exact_text: "", visible: :all)
  end

  def check_invalidated_preview
    expect(page).not_to have_css("[data-photo-card-target='preview']")
    expect(page).to have_css("img[data-photo-card-target='image']:not([src])", visible: :all)
    expect(page).to have_button("PNGをダウンロード", disabled: true, visible: :all)
  end

  def check_changed_settings
    expect(page).to have_css("[role='status']", text: "設定を変更しました。プレビューを作成してください。")
    check_invalidated_preview
  end

  def download_png
    click_button "PNGをダウンロード"
    expect(page).to have_css("[role='status']", text: "ダウンロードを開始しました。保存先をブラウザーで確認してください。", wait: 10)
    path = @download_directory.join("oshilog-card.png")
    page.document.synchronize(10, errors: [ Capybara::ExpectationNotMet ]) do
      unless path.file? && @download_directory.glob("*.crdownload").empty?
        raise Capybara::ExpectationNotMet, "Chrome has not finished downloading the PNG"
      end
    end
    expect(File.binread(path, 8)).to eq("\x89PNG\r\n\x1a\n".b)
    image = Vips::Image.new_from_file(path.to_s)
    expect(image.width).to be_positive
    expect(image.height).to be_positive
  end

  it "saves profile text and images, generates cards for one to four oshis and downloads the PNG" do
    others = (2..4).map do |index|
      create(:user_oshi, user: user, oshi: create(:oshi, :approved, name: "カードの推し#{index}"))
    end
    sign_in
    open_my_page
    click_link "プロフィール編集"
    within("main form") do
      fill_in "表示名（必須）", with: "カード利用者"
      fill_in "自己紹介", with: "ライブと舞台を楽しんでいます。"
      attach_file "プロフィール画像", fixture_image
      click_button "プロフィールを保存"
    end
    expect(page).to have_css("[role='status']", text: "プロフィールを更新しました。")
    click_link "プロフィール編集"
    expect(page).to have_field("表示名（必須）", with: "カード利用者")
    expect(page).to have_field("自己紹介", with: "ライブと舞台を楽しんでいます。")
    check_loaded_image("現在のプロフィール画像")

    within("nav[aria-label='グローバルナビゲーション']") { click_link "推し一覧" }
    within("main section.card", text: user_oshi.oshi.name) { click_link "編集", exact: true }
    attach_file "代表画像", fixture_image
    click_button "推し情報を更新"
    expect(page).to have_css("[role='status']", text: "推し情報を更新しました。")
    within("main section.card", text: user_oshi.oshi.name) { click_link "編集", exact: true }
    check_loaded_image("#{user_oshi.oshi.name}の現在の代表画像")

    open_card
    expect(page).to have_css("[data-frame-source]", count: 1)
    generate_preview
    others.each_with_index do |record, index|
      check record.oshi.name, exact: true
      expect(page).to have_css("[data-frame-source]", count: index + 2)
      check_changed_settings
      generate_preview
    end

    select "#{user_oshi.oshi.name}の代表画像", from: "2. #{others.first.oshi.name}の画像"
    expect(page).to have_select("2. #{others.first.oshi.name}の画像", selected: "#{user_oshi.oshi.name}の代表画像")
    check_changed_settings
    generate_preview
    select "画像を表示しない", from: "1. #{user_oshi.oshi.name}の画像"
    check_changed_settings
    generate_preview
    uncheck "保存済みの自己紹介を表示する"
    check_changed_settings
    generate_preview
    download_png

    open_card
    expect(page).to have_checked_field(user_oshi.oshi.name, exact: true)
    expect(page).to have_css("[data-frame-source]", count: 1)
    expect(page).not_to have_css("[data-photo-card-target='preview']")
    expect(page).to have_css("img[data-photo-card-target='image']:not([src])", visible: :all)
  end

  it "invalidates an old preview at download after source data is edited in another browser session" do
    create(:profile, user: user)
    sign_in
    open_card
    generate_preview

    Capybara.using_session(:profile_editor) do
      @editor_driver = page.driver
      sign_in
      open_my_page
      click_link "プロフィール編集"
      fill_in "表示名（必須）", with: "別画面で更新した表示名"
      click_button "プロフィールを保存"
      expect(page).to have_css("[role='status']", text: "プロフィールを更新しました。")
    end

    click_button "PNGをダウンロード"
    expect(page).to have_css("[role='alert']", text: "元データまたは画像が変更されたか、取得できません。再生成してください。", wait: 10)
    check_invalidated_preview
    expect(@download_directory.children).to be_empty
    generate_preview
    download_png
  end

  it "allows a visible preview and download when no representative image is registered" do
    create(:profile, user: user)
    sign_in
    open_card
    expect(page).to have_text("画像未登録でも作成できます。")
    generate_preview
    download_png
  end

  it "reports an unreadable registered image and recovers when that image is explicitly switched off" do
    create(:profile, user: user)
    user_oshi.representative_image.attach(image_upload)
    # Simulate loss of an original only in this example's isolated storage; there is no UI for this fault.
    blob = user_oshi.representative_image.blob
    blob.service.delete(blob.key)
    sign_in
    open_card
    click_button "プレビューを作成"
    expect(page).to have_css("[role='alert']", text: "登録画像を読み取れません。未登録とは異なる状態です。画像を確認してください。", wait: 10)
    check_invalidated_preview
    expect(@download_directory.children).to be_empty

    select "画像を表示しない", from: "1. #{user_oshi.oshi.name}の画像"
    check_changed_settings
    generate_preview
    download_png
  end
end
