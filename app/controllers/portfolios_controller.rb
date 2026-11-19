class PortfoliosController < ApplicationController
  before_action :set_household

  def show; end

  def update
    if @household.portfolio.update(portfolio_params)
      redirect_or_refresh_workspace portfolio_path, notice: 'Investment strategy updated successfully.'
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def portfolio_params
    permitted = params.expect(portfolio: %i[inflation_rate glidepath_id spending_smile_enabled])
    permitted[:inflation_rate] = permitted[:inflation_rate].to_d / 100 if permitted[:inflation_rate].present?
    permitted
  end

  def set_household
    @household = Current.user.household
  end
end
