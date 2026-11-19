class HouseholdsController < ApplicationController
  before_action :set_household, only: %i[show update]

  def show
    @spouse = @household.users.where.not(id: Current.user.id).first || User.new(household: @household)
  end

  def update
    if @household.update(household_params)
      redirect_or_refresh_workspace household_path
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_household
    @household = Current.user.household
  end

  def household_params
    params.expect(household: %i[province retirement_income_goal])
  end
end
