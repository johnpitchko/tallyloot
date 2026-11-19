# rubocop:disable Metrics/ClassLength
class SimulatorsController < ApplicationController
  include ChartRounding

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def show
    @household = Current.user.household
    @glidepaths = Glidepath.all
    @users_for_chart = @household.users.map { |u| { id: u.id, name: u.name, birth_year: u.birth_year } }

    @current_periods = Projection::Household.from_household(@household).periods

    @simulated_periods = if sim_params_present?
                           Simulation.new(@household, sim_params).projection.periods
                         else
                           @current_periods
                         end

    @net_worth_chart_data = build_net_worth_chart_data
    @income_chart_data = build_income_chart_data
    @net_worth_rows = build_net_worth_rows
    @income_rows = build_income_rows
    @summary_stats = build_summary_stats
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  private

  def sim_params_present?
    sim_params.values.any?(&:present?)
  end

  def sim_params
    @sim_params ||= params.permit(
      :retirement_income_goal, :glidepath_id,
      users: {},
      accounts: {},
      pensions: {},
      benefits: {}
    ).to_h
  end

  def build_net_worth_chart_data
    account_user_map = @household.accounts.each_with_object({}) { |a, h| h[a.id] = a.user_id }
    labels = @current_periods.map(&:year)
    {
      labels:,
      current: @current_periods.map(&:net_worth),
      simulated: @simulated_periods.map(&:net_worth),
      per_user: net_worth_per_user(labels, account_user_map),
    }
  end

  def net_worth_per_user(labels, account_user_map)
    current_by_year = @current_periods.index_by(&:year)
    simulated_by_year = @simulated_periods.index_by(&:year)
    @household.users.map do |user|
      {
        user_id: user.id,
        name: user.name,
        current: labels.map { |y| user_net_worth_for_period(current_by_year[y], user.id, account_user_map) },
        simulated: labels.map { |y| user_net_worth_for_period(simulated_by_year[y], user.id, account_user_map) },
      }
    end
  end

  def user_net_worth_for_period(period, user_id, account_user_map)
    return 0 unless period

    period.account_periods
          .select { |ap| account_user_map[ap.account_id] == user_id }
          .sum(&:ending_balance)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def build_income_chart_data
    # Income Projection covers the decumulation phase only — from full household
    # retirement onward (see DashboardsController / CLAUDE.md).
    current_by_year = @current_periods.select(&:fully_retired?).index_by(&:year)
    simulated_by_year = @simulated_periods.select(&:fully_retired?).index_by(&:year)
    all_years = (current_by_year.keys + simulated_by_year.keys).uniq.sort
    maps = income_user_maps

    current_income = all_years.map { |y| current_by_year[y]&.income_amount || 0 }
    simulated_income = all_years.map { |y| simulated_by_year[y]&.income_amount || 0 }

    {
      labels: all_years,
      current: round_series(current_income),
      simulated: round_series(simulated_income),
      current_real: round_series(deflated_income(all_years, current_by_year, current_income)),
      simulated_real: round_series(deflated_income(all_years, simulated_by_year, simulated_income)),
      income_goal: all_years.map { |y| round_to_nearest_thousand(simulated_by_year[y]&.nominal_income_goal || 0) },
      income_goal_real: all_years.map { |y| round_to_nearest_thousand(simulated_by_year[y]&.real_income_goal || 0) },
      per_user: income_per_user(all_years, current_by_year, simulated_by_year, maps),
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/AbcSize
  def income_user_maps
    {
      pension: @household.pensions.each_with_object({}) { |p, h| h[p.id] = p.user_id },
      benefit: @household.benefits.each_with_object({}) { |b, h| h[b.id] = b.user_id },
      account: @household.accounts.each_with_object({}) { |a, h| h[a.id] = a.user_id },
    }
  end
  # rubocop:enable Metrics/AbcSize

  def deflated_income(all_years, periods_by_year, income_amounts)
    all_years.each_with_index.map do |year, i|
      period = periods_by_year[year]
      period ? period.deflate(income_amounts[i]) : 0
    end
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def income_per_user(all_years, current_by_year, simulated_by_year, maps)
    @household.users.map do |user|
      current = all_years.map { |y| user_income_for_period(current_by_year[y], user.id, maps) }
      simulated = all_years.map { |y| user_income_for_period(simulated_by_year[y], user.id, maps) }
      {
        user_id: user.id,
        name: user.name,
        current: round_series(current),
        simulated: round_series(simulated),
        current_real: round_series(deflated_income(all_years, current_by_year, current)),
        simulated_real: round_series(deflated_income(all_years, simulated_by_year, simulated)),
      }
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
  def user_income_for_period(period, user_id, maps)
    return 0 unless period

    pension_inc = period.pension_periods
                        .select { |pp| maps[:pension][pp.pension_id] == user_id }
                        .sum(&:income_amount)
    benefit_inc = period.benefit_periods
                        .select { |bp| maps[:benefit][bp.benefit_id] == user_id }
                        .sum(&:income_amount)
    withdrawal_inc = period.account_periods
                           .select { |ap| maps[:account][ap.account_id] == user_id }
                           .sum(&:withdrawal_amount)
    pension_inc + benefit_inc + withdrawal_inc
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

  def build_summary_stats
    current_peak_nw   = @current_periods.map(&:net_worth).max || 0
    simulated_peak_nw = @simulated_periods.map(&:net_worth).max || 0
    {
      simulated_peak_net_worth: simulated_peak_nw,
      peak_net_worth_delta: simulated_peak_nw - current_peak_nw,
      simulated_avg_income: avg_retirement_income(@simulated_periods),
      avg_income_delta: avg_retirement_income(@simulated_periods) - avg_retirement_income(@current_periods),
    }
  end

  def avg_retirement_income(periods)
    retirement_periods = periods.select { |p| p.retired? && p.income_amount.positive? }
    return 0 if retirement_periods.empty?

    retirement_periods.sum { |p| p.deflate(p.income_amount) } / retirement_periods.size
  end

  def build_net_worth_rows
    current_by_year = @current_periods.index_by(&:year)
    simulated_by_year = @simulated_periods.index_by(&:year)
    all_years = (current_by_year.keys | simulated_by_year.keys).sort

    all_years.map do |year|
      cur = current_by_year[year]
      sim = simulated_by_year[year]
      cur_nw = cur&.net_worth || 0
      sim_nw = sim&.net_worth || 0
      { year:, current: cur_nw, simulated: sim_nw, delta: sim_nw - cur_nw }
    end
  end

  def build_income_rows
    current_by_year = @current_periods.index_by(&:year)
    simulated_by_year = @simulated_periods.index_by(&:year)
    all_years = (current_by_year.keys | simulated_by_year.keys).sort

    rows = all_years.map { |year| income_row(current_by_year[year], simulated_by_year[year], year) }
    rows.select { |r| r[:current_income].positive? || r[:simulated_income].positive? }
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def income_row(cur, sim, year)
    {
      year:,
      current_income: cur&.income_amount || 0,
      simulated_income: sim&.income_amount || 0,
      delta: (sim&.income_amount || 0) - (cur&.income_amount || 0),
      current_guaranteed: cur&.guaranteed_income || 0,
      simulated_guaranteed: sim&.guaranteed_income || 0,
      current_withdrawals: cur&.withdrawal_amount || 0,
      simulated_withdrawals: sim&.withdrawal_amount || 0,
      current_pension_periods: cur&.pension_periods || [],
      simulated_pension_periods: sim&.pension_periods || [],
      current_benefit_periods: cur&.benefit_periods || [],
      simulated_benefit_periods: sim&.benefit_periods || [],
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
end
# rubocop:enable Metrics/ClassLength
