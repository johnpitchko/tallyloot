# The dashboard edits records in Turbo Frames inside its input panel. After a
# save from one of those frames, a refresh stream reloads the whole dashboard so
# the summary and charts reflect the change. Requests from anywhere else (the
# standalone pages) get an ordinary redirect.
module RefreshesWorkspace
  extend ActiveSupport::Concern

  private

  def redirect_or_refresh_workspace(fallback_path, **)
    if turbo_frame_request?
      render turbo_stream: turbo_stream.refresh(request_id: nil)
    else
      redirect_to(fallback_path, **)
    end
  end
end
