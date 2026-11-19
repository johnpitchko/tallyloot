# Dismisses the "these are sample numbers" banner a self-hosted install shows
# until the person has made the starting household their own.
class SampleNoticesController < ApplicationController
  def destroy
    Current.user.household.update!(sample_data: false)
    redirect_to root_path
  end
end
