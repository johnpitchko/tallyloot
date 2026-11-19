class ProjectionsController < ApplicationController
  before_action :set_household_and_projection

  def show; end

  def details
    @tab = params[:tab].presence || 'net_worth'
    @account_type_names = @periods.first&.account_types&.map(&:type) || []
  end

  private

  def set_household_and_projection
    @user = Current.user
    @household = @user.household
    @projection = Projection::Household.from_household(@household)
    @periods = @projection.periods
  end
end
