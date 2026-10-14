RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 1024 ] do |options|
      options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"].present?
      # Chrome's warning about test credentials can block browser clicks.
      options.add_preference("profile.password_manager_leak_detection", false)
    end
  end
end
