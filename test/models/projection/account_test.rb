require 'test_helper'

module Projection
  class AccountTest < ActiveSupport::TestCase
    setup do
      @account = accounts(:rrsp_john)
      @portfolio = portfolios(:non_retired_portfolio)
      @projection = Projection::Account.new(@account, @portfolio)
      @start_year = Time.zone.now.year
      @end_year = @account.user.life_expectancy_year
    end

    test 'generate the correct number of periods' do
      periods = @projection.periods(@start_year, @end_year)

      assert_equal @end_year - @start_year + 1, periods.size
    end

    test 'generates correct periods for growth and contributions' do
      periods = @projection.periods(@start_year, @end_year)

      opening_balance = @account.balance || 0

      periods.each do |period|
        assert_equal opening_balance, period.opening_balance

        user_age = @account.user.age_in_year(period.year)
        expected_nominal_return = @portfolio.nominal_return_for_age(user_age)
        assert_in_delta expected_nominal_return, period.nominal_return, 0.0001

        expected_retired = @account.user.retired_as_of?(period.year)
        assert_equal expected_retired, period.retired

        # Standalone Projection::Account has no allocated withdrawals
        expected_withdrawal_amount = 0
        assert_equal expected_withdrawal_amount, period.withdrawal_amount

        expected_pre_growth_balance = (opening_balance + period.contribution_amount - expected_withdrawal_amount).round
        assert_equal expected_pre_growth_balance, period.pre_growth_balance

        expected_growth = (expected_pre_growth_balance * expected_nominal_return).round
        assert_equal expected_growth, period.growth

        expected_ending_balance = (expected_pre_growth_balance + expected_growth).round
        assert_equal expected_ending_balance, period.ending_balance

        opening_balance = expected_ending_balance
      end
    end
  end
end
