# Projection::Household generates multi-year financial projections for a household.
#
# This is the orchestrator that iterates from the current year to the terminal year
# (based on life expectancy), building a Period::Summary for each year.
#
# Key responsibilities:
# - Track account balances year-over-year (ending balance becomes next year's opening)
# - Use goal-based withdrawal allocation post-retirement (via Period::WithdrawalAllocation)
# - Coordinate Period::Account, Period::Pension, and Period::Benefit creation
#
# Usage:
#   projection = Projection::Household.new(household)
#   projection.periods  # => Array of Period::Summary objects, one per year
#
# The periods array is the main output, used by controllers to pass data to views.
#
module Projection
  class Household
    attr_reader :household, :accounts, :pensions, :benefits, :employments, :portfolio

    delegate :terminal_year, :retirement_income_goal, to: :household

    def self.from_household(household)
      new(
        household: household,
        portfolio: household.portfolio,
        users: household.users.to_a,
        accounts: household.accounts.to_a,
        pensions: household.pensions.to_a,
        benefits: household.benefits.to_a,
        employments: household.employments.includes(:user).to_a
      )
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(household:, portfolio:, users:, accounts:, pensions:, benefits:, employments: [])
      @household = household
      @portfolio = portfolio
      @users = users
      @accounts = accounts
      @pensions = pensions
      @benefits = benefits
      @employments = employments
    end
    # rubocop:enable Metrics/ParameterLists

    def periods
      opening_balances = initial_balances

      (current_year...terminal_year).map do |year|
        build_period_summary(year, opening_balances).tap do |summary|
          update_balances(opening_balances, summary.account_periods)
        end
      end
    end

    private

    def current_year
      Time.zone.now.year
    end

    def initial_balances
      accounts.index_with { |a| a.balance || 0 }
    end

    def update_balances(balances, account_periods)
      account_periods.each do |ap|
        account = accounts.find { |a| a.id == ap.account_id }
        balances[account] = ap.ending_balance if account
      end
    end

    # rubocop:disable Metrics/MethodLength
    def build_period_summary(year, opening_balances)
      pension_periods = build_pension_periods(year)
      benefit_periods = build_benefit_periods(year)
      employment_periods = build_employment_periods(year)
      account_periods = build_account_periods(year, opening_balances, pension_periods, benefit_periods)

      Period::Summary.new(
        year, portfolio,
        household: household,
        account_periods:,
        pension_periods:,
        benefit_periods:,
        employment_periods:
      )
    end
    # rubocop:enable Metrics/MethodLength

    def build_pension_periods(year)
      pensions.map { |p| Period::Pension.from_pension(p, portfolio, year) }
    end

    def build_benefit_periods(year)
      benefits.map { |b| Period::Benefit.from_benefit(b, portfolio, year) }
    end

    def build_employment_periods(year)
      employments.map { |e| Period::Employment.from_employment(e, year) }
    end

    def build_account_periods(year, opening_balances, pension_periods, benefit_periods)
      if household.retired_as_of?(year)
        build_account_periods_with_allocation(year, opening_balances, pension_periods, benefit_periods)
      else
        build_account_periods_without_withdrawals(year, opening_balances)
      end
    end

    def build_account_periods_without_withdrawals(year, opening_balances)
      accounts.map do |account|
        user = @users.find { |u| u.id == account.user_id }
        Period::Account.from_account(account, portfolio, year, user: user, opening_balance: opening_balances[account])
      end
    end

    def build_account_periods_with_allocation(year, opening_balances, pension_periods, benefit_periods)
      allocation = build_withdrawal_allocation(year, opening_balances, pension_periods, benefit_periods)

      accounts.map do |account|
        user = @users.find { |u| u.id == account.user_id }
        Period::Account.from_account(
          account, portfolio, year,
          user: user,
          opening_balance: opening_balances[account],
          allocated_withdrawal: allocation.withdrawal_for(account)
        )
      end
    end

    def build_withdrawal_allocation(year, opening_balances, pension_periods, benefit_periods)
      employment_periods = build_employment_periods(year)
      Period::WithdrawalAllocation.new(
        year: year,
        income_goal: nominal_income_goal(year),
        guaranteed_income: pension_periods.sum(&:income_amount) +
                           benefit_periods.sum(&:income_amount) +
                           employment_periods.sum(&:income_amount),
        account_balances: accounts.map { |a| { account: a, balance: opening_balances[a] } },
        user_ages: user_ages_for_year(year)
      )
    end

    def nominal_income_goal(year)
      return retirement_income_goal if retirement_income_goal.nil? || retirement_income_goal.zero?

      inflated = inflate_to_year(retirement_income_goal, current_year, year)
      eldest = household.eldest_user
      multiplier = portfolio.spending_smile_for(eldest).multiplier_for_age(eldest.age_in_year(year))
      (inflated * multiplier).round
    end

    def inflate_to_year(amount, base_year, target_year)
      return amount if base_year.nil? || target_year <= base_year

      rate = portfolio&.inflation_rate || 0.02
      (amount * ((1 + rate)**(target_year - base_year))).round
    end

    def user_ages_for_year(year)
      @users.to_h { |u| [u.id, u.age_in_year(year)] }
    end
  end
end
