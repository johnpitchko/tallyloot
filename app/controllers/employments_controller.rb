class EmploymentsController < ApplicationController
  before_action :set_household
  before_action :set_user, only: %i[edit update]
  before_action :set_employment, only: %i[edit update]

  def index; end

  def edit; end

  def update
    if @employment.update(employment_params)
      redirect_or_refresh_workspace employments_path, notice: 'Employment was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_household
    @household = Current.user.household
  end

  def set_user
    @user = @household.users.find(params[:user_id])
  end

  def set_employment
    @employment = @user.employment
  end

  def employment_params
    params.expect(
      employment: %i[label annual_income start_age end_age currency_code]
    )
  end
end
