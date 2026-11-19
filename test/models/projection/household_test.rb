require 'test_helper'

module Projection
  class HouseholdTest < ActiveSupport::TestCase
    setup do
      @household = households(:non_retired)
      @projection = Projection::Household.from_household(@household)
    end

    # FIXME: this is a jank test that will fail after 2025 because the terminal year of the household is fixed to the
    # life expectancy of the test users, which is a static value in the fixture.
    test 'periods has correct number of periods' do
      expected_count = @household.terminal_year - Time.zone.now.year
      assert_equal expected_count, @projection.periods.count
    end

    # John retires 2045, Jane retires 2046 — the household is only fully retired once both have.
    test 'period is fully_retired only once every member has retired' do
      periods_by_year = @projection.periods.index_by(&:year)

      assert periods_by_year[2045].retired?, 'John is retired in 2045'
      assert_not periods_by_year[2045].fully_retired?, 'Jane still works in 2045, so not fully retired'
      assert periods_by_year[2046].fully_retired?, 'Both members are retired by 2046'
    end

    # Spending smile tests
    # non_retired household: eldest user (John) born 1980, retirement_age: 65, life_expectancy: 82
    # retirement_year = 2045, trough at age 80 (year 2060), terminal at age 82 (year 2062)
    # Jane (youngest) born 1981, retirement_age: 65, life_expectancy: 82

    def inflated_goal(year)
      inflation_rate = @household.portfolio.inflation_rate
      (@household.retirement_income_goal * ((1 + inflation_rate)**(year - Time.zone.now.year))).round
    end

    test 'nominal_income_goal with spending smile disabled returns flat inflated goal' do
      @household.portfolio.spending_smile_enabled = false
      projection = Projection::Household.from_household(@household)

      year = @household.retirement_year + 5
      assert_equal inflated_goal(year), projection.send(:nominal_income_goal, year)
    end

    test 'nominal_income_goal at retirement age returns unmodified inflated goal' do
      @household.portfolio.spending_smile_enabled = true
      projection = Projection::Household.from_household(@household)

      # At retirement year, eldest is exactly at retirement_age → multiplier = 1.0
      assert_equal inflated_goal(@household.retirement_year), projection.send(:nominal_income_goal, @household.retirement_year)
    end

    test 'nominal_income_goal declines linearly during decline phase' do
      @household.portfolio.spending_smile_enabled = true
      projection = Projection::Household.from_household(@household)

      # John at age 72 (year 2052): t = (72-65)/(80-65) = 7/15, multiplier = 1.0 - (7/15)*0.30
      year = 2052
      t = (72 - 65).to_f / (80 - 65)
      expected_multiplier = 1.0 - t * 0.30
      expected = (inflated_goal(year) * expected_multiplier).round

      assert_equal expected, projection.send(:nominal_income_goal, year)
    end

    test 'nominal_income_goal applies trough multiplier at age 80' do
      @household.portfolio.spending_smile_enabled = true
      projection = Projection::Household.from_household(@household)

      # John at age 80 (year 2060): trough
      year = 2060
      expected = (inflated_goal(year) * SpendingSmile::TROUGH_MULTIPLIER).round

      assert_equal expected, projection.send(:nominal_income_goal, year)
    end

    test 'nominal_income_goal applies terminal multiplier at life expectancy' do
      @household.portfolio.spending_smile_enabled = true
      projection = Projection::Household.from_household(@household)

      # John at age 82 (year 2062): terminal
      year = 2062
      expected = (inflated_goal(year) * SpendingSmile::TERMINAL_MULTIPLIER).round

      assert_equal expected, projection.send(:nominal_income_goal, year)
    end

    test 'nominal_income_goal uses eldest users age not youngest' do
      @household.portfolio.spending_smile_enabled = true
      projection = Projection::Household.from_household(@household)

      # Year 2060: John (eldest, born 1980) is 80 → trough multiplier (0.70)
      #            Jane (youngest, born 1981) is 79 → t=14/15, multiplier ≈ 0.72
      # If youngest were used the result would differ
      year = 2060
      expected = (inflated_goal(year) * SpendingSmile::TROUGH_MULTIPLIER).round

      assert_equal expected, projection.send(:nominal_income_goal, year)
    end
  end
end
