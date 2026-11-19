class WhatIfsController < ApplicationController
  include ChartRounding

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def show
    @household = Current.user.household
    @users_for_chart = @household.users.map { |u| { id: u.id, name: u.name, birth_year: u.birth_year } }
    @current_periods = Projection::Household.from_household(@household).periods

    @warnings = []
    if what_if_params_present?
      @what_if = WhatIf.new(@household, what_if_params)
      @warnings = @what_if.warnings
      if @warnings.none?
        @what_if_periods = @what_if.projection.periods
        @insights = @what_if.adjustments
      else
        @what_if_periods = @current_periods
        @insights = []
      end
    else
      @what_if_periods = @current_periods
      @insights = []
    end

    @net_worth_chart_data = build_net_worth_chart_data
    @income_chart_data = build_income_chart_data
    @summary_stats = build_summary_stats
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

  def what_if_params_present?
    what_if_params.values.any?(&:present?)
  end

  def what_if_params
    @what_if_params ||= params.permit(
      users: {}, benefits: {}, employments: {}
    ).to_h
  end

  def build_net_worth_chart_data
    labels = @current_periods.map(&:year)
    {
      labels:,
      current: @current_periods.map(&:net_worth),
      simulated: @what_if_periods.map(&:net_worth),
    }
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def build_income_chart_data
    # Income Projection covers the decumulation phase only — from full household
    # retirement onward (see DashboardsController / CLAUDE.md).
    current_by_year = @current_periods.select(&:fully_retired?).index_by(&:year)
    what_if_by_year = @what_if_periods.select(&:fully_retired?).index_by(&:year)
    all_years = (current_by_year.keys + what_if_by_year.keys).uniq.sort

    {
      labels: all_years,
      current: all_years.map { |y| round_to_nearest_thousand(current_by_year[y]&.income_amount || 0) },
      simulated: all_years.map { |y| round_to_nearest_thousand(what_if_by_year[y]&.income_amount || 0) },
      current_real: all_years.map { |y| round_to_nearest_thousand(deflated_income(current_by_year[y])) },
      simulated_real: all_years.map { |y| round_to_nearest_thousand(deflated_income(what_if_by_year[y])) },
      income_goal: all_years.map { |y| round_to_nearest_thousand(what_if_by_year[y]&.nominal_income_goal || 0) },
      income_goal_real: all_years.map { |y| round_to_nearest_thousand(what_if_by_year[y]&.real_income_goal || 0) },
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def deflated_income(period)
    return 0 unless period

    period.deflate(period.income_amount)
  end

  def build_summary_stats
    current_peak_nw = @current_periods.map(&:net_worth).max || 0
    what_if_peak_nw = @what_if_periods.map(&:net_worth).max || 0
    {
      what_if_peak_net_worth: what_if_peak_nw,
      peak_net_worth_delta: what_if_peak_nw - current_peak_nw,
      what_if_avg_income: avg_retirement_income(@what_if_periods),
      avg_income_delta: avg_retirement_income(@what_if_periods) - avg_retirement_income(@current_periods),
    }
  end

  def avg_retirement_income(periods)
    retirement_periods = periods.select { |p| p.retired? && p.income_amount.positive? }
    return 0 if retirement_periods.empty?

    retirement_periods.sum { |p| p.deflate(p.income_amount) } / retirement_periods.size
  end
end
