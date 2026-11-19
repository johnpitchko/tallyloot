# rubocop:disable Metrics/ClassLength
class DashboardsController < ApplicationController
  include ChartRounding

  # rubocop:disable Metrics/MethodLength
  def show
    @user = Current.user
    @household = @user.household
    @projection = Projection::Household.from_household(@household)
    @periods = @projection.periods
    @accounts = @household.accounts
    @account_data = prepare_account_data
    # Income Projection covers the decumulation phase only: start once the whole
    # household is retired, so a still-working member's (unmodelled) salary is
    # never shown as a misleadingly low-income year. See CLAUDE.md.
    @income_periods = @periods.select(&:fully_retired?)
    @income_data = prepare_income_data
    @real_income_data = prepare_real_income_data
    @summary = prepare_summary
    @users_for_filter = prepare_users_for_filter
    @crossover_data = prepare_crossover_data
  end
  # rubocop:enable Metrics/MethodLength

  private

  def prepare_summary
    retirement_year = earliest_retirement_year
    {
      current_net_worth: @periods.first&.net_worth || 0,
      retirement_net_worth: net_worth_at_year(retirement_year),
      years_to_retirement: years_until(retirement_year),
      retirement_year: retirement_year,
      avg_retirement_income: avg_retirement_income,
    }
  end

  def avg_retirement_income
    retirement_periods = @periods.select { |p| p.retired? && p.income_amount.positive? }
    return 0 if retirement_periods.empty?

    retirement_periods.sum { |p| p.deflate(p.income_amount) } / retirement_periods.size
  end

  def earliest_retirement_year
    @household.users.map(&:retirement_year).compact.min
  end

  def years_until(year)
    return nil unless year

    [year - Time.zone.now.year, 0].max
  end

  def net_worth_at_year(year)
    return 0 unless year

    @periods.find { |p| p.year == year }&.net_worth || 0
  end

  # rubocop:disable Metrics/MethodLength
  def prepare_account_data
    # Build series data for each account with user ownership
    @accounts.includes(:user).map do |account|
      {
        name: account.name,
        user_id: account.user_id,
        user_name: account.user.name,
        data: @periods.map do |period|
          account_period = period.account_periods.find { |ap| ap.account_id == account.id }
          account_period ? account_period.ending_balance : 0
        end,
      }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def prepare_crossover_data
    cutoff = @household.retirement_year
    household_periods = periods_before(cutoff)
    household = Crossover.for_household(household_periods).to_h(user_id: 'all')
    users = @household.users.map { |u| crossover_for_user(u) }
    [household] + users
  end

  def crossover_for_user(user)
    user_periods = periods_before(user.retirement_year)
    Crossover.for_user(user_periods, user).to_h(user_id: user.id, user_name: user.name)
  end

  def periods_before(cutoff_year)
    return @periods unless cutoff_year

    @periods.select { |p| p.year < cutoff_year }
  end

  def prepare_users_for_filter
    @household.users.map do |user|
      { id: user.id, name: user.name, birth_year: user.birth_year }
    end
  end

  def prepare_income_data
    build_income_data { |_period, amount| round_to_nearest_thousand(amount) }
  end

  def prepare_real_income_data
    data = build_income_data { |period, amount| round_to_nearest_thousand(period.deflate(amount)) }
    # Override income_goal: use real_income_goal directly (matches Income details table "Real" column)
    data[:income_goal] = build_income_goal_real_data
    data
  end

  def build_income_goal_data
    return nil unless @household.retirement_income_goal.to_i.positive?

    @income_periods.map { |period| period.retired? ? round_to_nearest_thousand(period.nominal_income_goal) : nil }
  end

  def build_income_goal_real_data
    return nil unless @household.retirement_income_goal.to_i.positive?

    @income_periods.map { |period| period.retired? ? round_to_nearest_thousand(period.real_income_goal) : nil }
  end

  # rubocop:disable Metrics/MethodLength
  def build_income_data(&transform)
    {
      withdrawals: build_withdrawal_data(&transform),
      employments: build_employment_data(&transform),
      pensions: build_pension_data(&transform),
      benefits: build_benefit_data(&transform),
      total_income: @income_periods.map { |p| transform.call(p, p.income_amount) },
      net_total_income: @income_periods.map { |p| transform.call(p, p.after_tax_income) },
      estimated_tax: @income_periods.map { |p| transform.call(p, p.tax_estimate.estimated_tax) },
      income_goal: build_income_goal_data(&transform),
    }
  end

  def build_withdrawal_data(&transform)
    @accounts.includes(:user).map do |account|
      {
        name: account.name,
        user_id: account.user_id,
        user_name: account.user.name,
        data: @income_periods.map do |period|
          account_period = period.account_periods.find { |ap| ap.account_id == account.id }
          amount = account_period ? account_period.withdrawal_amount : 0
          transform.call(period, amount)
        end,
      }
    end
  end

  def build_pension_data(&transform)
    @household.pensions.includes(:user).map do |pension|
      {
        name: pension.name,
        user_id: pension.user_id,
        user_name: pension.user.name,
        data: @income_periods.map do |period|
          pension_period = period.pension_periods.find { |pp| pp.pension_id == pension.id }
          amount = pension_period ? pension_period.income_amount : 0
          transform.call(period, amount)
        end,
      }
    end
  end

  def build_benefit_data(&transform)
    @household.benefits.includes(:user).map do |benefit|
      {
        name: benefit.name,
        user_id: benefit.user_id,
        user_name: benefit.user.name,
        data: @income_periods.map do |period|
          benefit_period = period.benefit_periods.find { |bp| bp.benefit_id == benefit.id }
          amount = benefit_period ? benefit_period.income_amount : 0
          transform.call(period, amount)
        end,
      }
    end
  end

  def build_employment_data(&transform)
    @household.employments.includes(:user).map do |employment|
      {
        name: employment.label.presence || 'Post-retirement employment',
        user_id: employment.user_id,
        user_name: employment.user.name,
        data: @income_periods.map do |period|
          employment_period = period.employment_periods.find { |ep| ep.employment_id == employment.id }
          amount = employment_period ? employment_period.income_amount : 0
          transform.call(period, amount)
        end,
      }
    end
  end
  # rubocop:enable Metrics/MethodLength
end
# rubocop:enable Metrics/ClassLength
