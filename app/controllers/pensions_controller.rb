class PensionsController < ApplicationController
  before_action :set_household
  before_action :set_user, except: %i[index]
  before_action :set_pension, only: %i[edit update destroy]

  def index; end

  def new
    @pension = @user.pensions.new
  end

  def edit; end

  def create
    @pension = @user.pensions.new(pension_params)

    if @pension.save
      redirect_or_refresh_workspace pensions_path, notice: 'Pension was successfully created.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @pension.update(pension_params)
      redirect_or_refresh_workspace pensions_path, notice: 'Pension was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @pension.destroy
    redirect_or_refresh_workspace pensions_path, notice: 'Pension was successfully deleted.'
  end

  private

  def set_household
    @household = Current.user.household
  end

  def set_user
    @user = @household.users.find(params[:user_id])
  end

  def set_pension
    @pension = @household.pensions.find(params[:id])
  end

  def pension_params
    params.expect(
      pension: %i[name annual_amount start_age inflation_indexed description
                  normal_retirement_age early_reduction_rate_pct late_increase_rate_pct]
    )
  end
end
