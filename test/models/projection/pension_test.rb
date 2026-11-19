require 'test_helper'

module Projection
  class PensionTest < ActiveSupport::TestCase
    setup do
      @pension = pensions(:indexed)
      @portfolio = portfolios(:non_retired_portfolio)
      @projection = Projection::Pension.new(@pension, @portfolio)
      @start_year = Time.zone.now.year
      @end_year = @pension.user.life_expectancy_year
    end

    test 'generate the correct number of periods' do
      periods = @projection.periods(@start_year, @end_year)

      assert_equal @end_year - @start_year, periods.size
    end

    test 'generates correct periods' do
      periods = @projection.periods(@start_year, @end_year)

      periods.each do |period|
        @pension.user.age_in_year(period.year)
        expected_amount = if period.year < @pension.start_year
                            0
                          else
                            years_since_start = period.year - @pension.start_year
                            growth_factor = (1 + @portfolio.inflation_rate)**years_since_start
                            @pension.annual_amount * growth_factor
                          end
        assert_in_delta expected_amount, period.income_amount, 1.00
      end
    end
  end
end
