require 'test_helper'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include TestOwner::Helpers

  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  teardown do
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end
