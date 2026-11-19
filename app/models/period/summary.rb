# Period::Summary represents a household's complete financial snapshot for a single year.
#
# It aggregates data from all accounts, pensions, and benefits to provide totals for:
# - Net worth (opening/ending balances)
# - Cash flows (contributions, withdrawals, growth)
# - Income (from pensions, benefits, and account withdrawals)
# - Income goal tracking (real vs nominal, shortfall/surplus)
#
# This is the primary object used by views to display yearly projection data.
# It's created by Projection::Household which handles the year-over-year iteration.
#
# Key relationships:
# - Contains many Period::Account objects (one per account)
# - Contains many Period::Pension objects (one per pension)
# - Contains many Period::Benefit objects (one per benefit)
# - Can generate Period::AccountType summaries for grouped display
#
# rubocop:disable Metrics/ClassLength
module Period
  class Summary
    include Inspectable

    attr_reader :year, :portfolio, :account_periods, :pension_periods, :benefit_periods, :employment_periods

    inspectable :year, :contribution_amount, :withdrawal_amount, :income_amount, :ending_balance

    # rubocop:disable Metrics/ParameterLists
    def initialize(year, portfolio, household: nil, account_periods: [], pension_periods: [], benefit_periods: [],
                   employment_periods: [])
      @year = year
      @portfolio = portfolio
      @household = household
      @account_periods = Array(account_periods)
      @pension_periods = Array(pension_periods)
      @benefit_periods = Array(benefit_periods)
      @employment_periods = Array(employment_periods)
    end
    # rubocop:enable Metrics/ParameterLists

    def income_amount
      guaranteed_income + employment_income + withdrawal_amount
    end

    def guaranteed_income
      pension_income + benefit_income
    end

    def real_income_goal
      base = @household&.retirement_income_goal || 0
      return base unless retired?

      (base * spending_smile_multiplier).round
    end

    # Nominal income goal adjusts for inflation from the retirement year.
    # real_income_goal already incorporates the smile multiplier, so we just inflate it.
    def nominal_income_goal
      return 0 unless retired?

      inflate(real_income_goal, from_year: Time.zone.now.year)
    end

    # Converts a real (today's) dollar amount into nominal (future) dollars
    # by compounding inflation forward from `from_year` to this period's year.
    #
    # This is the inverse of #deflate: where deflate discounts a future nominal
    # amount back to today's dollars, inflate projects a present-day amount
    # forward to what it would need to be in future dollars.
    #
    # Returns the original amount unchanged when:
    # - the amount is zero
    # - from_year is nil (no reference point for inflation)
    # - from_year is at or after this period's year (no inflation to apply)
    #
    # Example: inflate(50_000, from_year: 2025) in year 2030 at 2% inflation
    #   => 50_000 * (1.02 ** 5) => 55,204
    def inflate(real_amount, from_year:)
      return real_amount if real_amount.zero? || from_year.nil?

      years_elapsed = year - from_year
      return real_amount if years_elapsed <= 0

      (real_amount * ((1 + inflation_rate)**years_elapsed)).round
    end

    def income_shortfall
      return 0 unless retired?

      [nominal_income_goal - income_amount, 0].max
    end

    def income_surplus
      return 0 unless retired?

      [income_amount - nominal_income_goal, 0].max
    end

    def retired?
      @household&.retired_as_of?(year) || false
    end

    # True only once every household member has retired. The Income Projection
    # renders from the first fully-retired year onward.
    def fully_retired?
      @household&.fully_retired_as_of?(year) || false
    end

    def net_worth
      ending_balance
    end

    def contribution_amount
      account_periods.sum(&:contribution_amount)
    end

    def withdrawal_amount
      account_periods.sum(&:withdrawal_amount)
    end

    def growth
      account_periods.sum(&:growth)
    end

    def opening_balance
      account_periods.sum(&:opening_balance)
    end

    def ending_balance
      account_periods.sum(&:ending_balance)
    end

    # Total change in value for the year (contributions - withdrawals + growth)
    def net_change
      ending_balance - opening_balance
    end

    def pre_growth_balance
      account_periods.sum(&:pre_growth_balance)
    end

    def nominal_return
      0
    end

    def pension_income
      pension_periods.sum(&:income_amount)
    end

    def benefit_income
      benefit_periods.sum(&:income_amount)
    end

    # Post-retirement earned income from Employment records.
    # Returns 0 until Projection::Household is updated to pass employment_periods.
    # TODO: OAS clawback PR - wire employment_periods through Projection::Household,
    # then apply the clawback reduction to OAS benefit_income when
    # taxable_income exceeds the annual threshold (~$90,997 in 2024, inflation-indexed).
    def employment_income
      employment_periods.sum(&:income_amount)
    end

    def taxable_withdrawal_amount
      account_periods.select { |ap| ap.account&.taxable? }.sum(&:withdrawal_amount)
    end

    def taxable_income
      pension_income + benefit_income + employment_income + taxable_withdrawal_amount
    end

    def tax_estimate
      @tax_estimate ||= begin
        rate = inflation_rate
        federal = Tax::FederalBrackets.new(year: year, inflation_rate: rate, province: @household&.province)
        provincial = Tax::ProvincialBrackets.new(year: year, inflation_rate: rate, province: @household&.province)
        Period::TaxEstimate.new(
          taxable_income: taxable_income,
          federal_tax: federal.tax_on(taxable_income),
          provincial_tax: provincial.tax_on(taxable_income)
        )
      end
    end

    def after_tax_income
      income_amount - tax_estimate.estimated_tax
    end

    def deflate(nominal_amount)
      return nominal_amount if nominal_amount.zero?

      years_elapsed = year - Time.zone.now.year
      return nominal_amount if years_elapsed <= 0

      (nominal_amount / ((1 + inflation_rate)**years_elapsed)).round
    end

    def user_age
      @household&.eldest_user&.age_in_year(year)
    end

    def household_ages
      @household&.user_ages_in_year(year)
    end

    def account_types
      @account_types ||= account_periods
                         .group_by { |ap| ap.account.type }
                         .map { |type, periods| AccountType.new(type: type, account_periods: periods) }
                         .sort_by(&:type_name)
    end

    private

    def inflation_rate
      portfolio&.inflation_rate || 0.02
    end

    def spending_smile_multiplier
      eldest = @household&.eldest_user
      portfolio.spending_smile_for(eldest).multiplier_for_age(user_age)
    end
  end
end
# rubocop:enable Metrics/ClassLength
