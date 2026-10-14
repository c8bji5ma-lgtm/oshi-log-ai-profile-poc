class ApplicationController < ActionController::Base
  before_action :authenticate_user!, unless: :devise_controller?

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  protected

  def html_navigation_request?
    request.format.html? || request.format.turbo_stream?
  end

  def render_user_data_not_found(error)
    raise error unless html_navigation_request?

    render "errors/not_found", formats: [ :html ], status: :not_found
  end

  def after_sign_out_path_for(_resource_or_scope)
    new_user_session_path
  end
end
