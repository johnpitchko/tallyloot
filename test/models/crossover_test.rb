require 'test_helper'

class CrossoverTest < ActiveSupport::TestCase
  FakePeriod = Struct.new(:year, :contribution_amount, :growth, :account_periods)
  FakeAccountPeriod = Struct.new(:account_id, :contribution_amount, :growth)

  def make_periods(rows)
    rows.map do |year, contributions, growth|
      FakePeriod.new(year, contributions, growth, [])
    end
  end

  test 'detects crossover year and amount when growth exceeds contributions' do
    periods = make_periods([
      [2026, 10_000, 5_000],
      [2027, 10_000, 12_000],
      [2028, 10_000, 15_000],
    ])

    crossover = Crossover.for_household(periods)

    assert crossover.reached?
    assert_equal 2027, crossover.year
    assert_equal 12_000, crossover.amount
  end

  test 'detects crossover year when growth equals contributions exactly' do
    periods = make_periods([
      [2026, 10_000, 9_000],
      [2027, 10_000, 10_000],
    ])

    crossover = Crossover.for_household(periods)

    assert crossover.reached?
    assert_equal 2027, crossover.year
  end

  test 'returns nil year and amount when no crossover in series' do
    periods = make_periods([
      [2026, 10_000, 3_000],
      [2027, 10_000, 5_000],
      [2028, 10_000, 8_000],
    ])

    crossover = Crossover.for_household(periods)

    assert_not crossover.reached?
    assert_nil crossover.year
    assert_nil crossover.amount
  end

  test 'skips zero-contribution years when detecting crossover' do
    periods = make_periods([
      [2026, 10_000, 5_000],
      [2027, 0, 50_000],   # retired — should be skipped
      [2028, 0, 60_000],   # retired — should be skipped
    ])

    crossover = Crossover.for_household(periods)

    assert_not crossover.reached?
  end

  test 'to_h returns correctly structured hash for household' do
    periods = make_periods([
      [2026, 10_000, 5_000],
      [2027, 10_000, 12_000],
    ])

    result = Crossover.for_household(periods).to_h(user_id: 'all')

    assert_equal 'all', result[:user_id]
    assert_nil result[:user_name]
    assert_equal [2026, 2027], result[:years]
    assert_equal [10_000, 10_000], result[:contributions]
    assert_equal [5_000, 12_000], result[:growth]
    assert_equal 2027, result[:crossover_year]
    assert_equal 12_000, result[:crossover_amount]
  end

  test 'to_h returns nil crossover fields when no crossover' do
    periods = make_periods([[2026, 10_000, 1_000]])

    result = Crossover.for_household(periods).to_h(user_id: 'all')

    assert_nil result[:crossover_year]
    assert_nil result[:crossover_amount]
  end

  test 'for_user filters account periods by user account ids' do
    account_period_1 = FakeAccountPeriod.new(1, 8_000, 500)
    account_period_2 = FakeAccountPeriod.new(2, 2_000, 100)

    period = FakePeriod.new(2026, 10_000, 600, [account_period_1, account_period_2])

    user = Struct.new(:account_ids).new([1])

    crossover = Crossover.for_user([period], user)
    entry = crossover.series.first

    assert_equal 8_000, entry[:contributions]
    assert_equal 500, entry[:growth]
  end
end
