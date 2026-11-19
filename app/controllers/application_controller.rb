class ApplicationController < ActionController::Base
  include RefreshesWorkspace

  # Each install serves one household and has no login; every request acts as
  # that household's first member.
  before_action :set_current_user

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  private

  def set_current_user
    Current.user = SelfHosted.owner
  end
end
