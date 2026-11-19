class AccountsController < ApplicationController
  before_action :set_household
  before_action :set_user, except: %i[index]
  before_action :set_account, only: %i[edit update destroy]

  def index
    @accounts = @household.accounts
  end

  def new
    if params[:type].present? && params[:type].in?(Account::TYPES)
      @account = @user.accounts.new(type: params[:type])
    else
      render :select_type
    end
  end

  def edit; end

  def create
    @account = @user.accounts.new(account_params)

    if @account.save
      redirect_or_refresh_workspace accounts_path, notice: 'Account was successfully created.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @account.update(account_params)
      redirect_or_refresh_workspace accounts_path, notice: 'Account was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @account.destroy
    redirect_or_refresh_workspace accounts_path, notice: 'Account was successfully deleted.'
  end

  private

  def set_household
    @household = Current.user.household
  end

  def set_user
    @user = @household.users.find(params[:user_id])
  end

  def set_account
    @account = @household.accounts.find(params[:id])
  end

  # The owner can be changed from the form, but only to someone in this household.
  def account_params
    attributes = params.expect(
      account: %i[name type balance contribution conversion_age provincial_jurisdiction user_id]
    )
    attributes[:user] = @household.users.find(attributes.delete(:user_id)) if attributes[:user_id].present?
    attributes
  end
end
