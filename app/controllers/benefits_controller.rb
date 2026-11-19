class BenefitsController < ApplicationController
  before_action :set_household
  before_action :set_user, except: %i[index]
  before_action :set_benefit, only: %i[edit update destroy]

  def index; end

  def new
    if params[:type].present? && params[:type].in?(Benefit::TYPES)
      @benefit = @user.benefits.new(type: params[:type])
    else
      render :select_type
    end
  end

  def edit; end

  def create
    @benefit = @user.benefits.new(benefit_params)

    if @benefit.save
      redirect_or_refresh_workspace benefits_path, notice: 'Benefit was successfully created.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @benefit.update(benefit_params)
      redirect_or_refresh_workspace benefits_path, notice: 'Benefit was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @benefit.destroy
    redirect_or_refresh_workspace benefits_path, notice: 'Benefit was successfully deleted.'
  end

  private

  def set_household
    @household = Current.user.household
  end

  def set_user
    @user = @household.users.find(params[:user_id])
  end

  def set_benefit
    @benefit = @household.benefits.find(params[:id])
  end

  def benefit_params
    params.expect(
      benefit: %i[name type annual_amount start_age inflation_indexed]
    )
  end
end
