class UsersController < ApplicationController
  before_action :set_household
  before_action :set_user, only: %i[edit update]

  def new
    @user = @household.users.build
  end

  def edit; end

  def create
    @spouse = @household.users.build(user_params)
    if @spouse.save
      redirect_or_refresh_workspace household_path, notice: "#{@spouse.name} has been added to your household."
    elsif turbo_frame_request?
      @user = @spouse
      render :new, status: :unprocessable_content
    else
      render 'households/show', status: :unprocessable_content
    end
  end

  def update
    if @user.update(user_params)
      redirect_or_refresh_workspace redirect_path,
                                    notice: "#{@user.name}'s #{resource_name} updated successfully."
    elsif turbo_frame_request?
      render :edit, status: :unprocessable_content
    else
      redirect_to redirect_path, alert: "Failed to update #{@user.name}'s #{resource_name}."
    end
  end

  private

  def set_household
    @household = Current.user.household
  end

  def set_user
    @user = @household.users.find(params[:id])
  end

  def user_params
    params.expect(
      user: %i[name birth_date retirement_age life_expectancy]
    )
  end

  def redirect_path
    case params[:source]
    when 'pensions' then pensions_path
    when 'benefits' then benefits_path
    when 'household' then household_path
    else portfolio_path
    end
  end

  def resource_name
    case params[:source]
    when 'pensions' then 'pensions'
    when 'benefits' then 'benefits'
    when 'household' then 'profile'
    else 'accounts'
    end
  end
end
