require 'test_helper'

class SpendingSmileTest < ActiveSupport::TestCase
  RETIREMENT_AGE = 65
  TERMINAL_AGE   = 82

  def smile(enabled: true, retirement_age: RETIREMENT_AGE, terminal_age: TERMINAL_AGE)
    SpendingSmile.new(retirement_age: retirement_age, terminal_age: terminal_age, enabled: enabled)
  end

  test 'returns 1.0 at all ages when disabled' do
    s = smile(enabled: false)

    assert_equal 1.0, s.multiplier_for_age(65)
    assert_equal 1.0, s.multiplier_for_age(75)
    assert_equal 1.0, s.multiplier_for_age(88)
  end

  test 'returns 1.0 at retirement age' do
    assert_equal 1.0, smile.multiplier_for_age(RETIREMENT_AGE)
  end

  test 'declines linearly from retirement age to trough at 80' do
    # At age 72: t = 7/15, multiplier = 1.0 - (7/15)*0.30 ≈ 0.86
    assert_in_delta 0.85, smile.multiplier_for_age(72), 0.02
    # At age 75: t = 10/15, multiplier = 1.0 - (10/15)*0.30 ≈ 0.80
    assert_in_delta 0.80, smile.multiplier_for_age(75), 0.005
  end

  test 'returns trough multiplier at age 80' do
    assert_in_delta SpendingSmile::TROUGH_MULTIPLIER, smile.multiplier_for_age(80), 0.001
  end

  test 'rises linearly from trough to terminal multiplier' do
    # At age 81 (midpoint between 80 and 82): t = 0.5
    expected = SpendingSmile::TROUGH_MULTIPLIER +
               0.5 * (SpendingSmile::TERMINAL_MULTIPLIER - SpendingSmile::TROUGH_MULTIPLIER)
    assert_in_delta expected, smile.multiplier_for_age(81), 0.001
  end

  test 'caps at terminal multiplier at and beyond terminal age' do
    assert_in_delta SpendingSmile::TERMINAL_MULTIPLIER, smile.multiplier_for_age(TERMINAL_AGE), 0.001
    assert_in_delta SpendingSmile::TERMINAL_MULTIPLIER, smile.multiplier_for_age(TERMINAL_AGE + 5), 0.001
  end

  test 'curve adjusts when retirement age changes' do
    # With retirement_age=70, at age 75: t = 5/10 = 0.5, multiplier = 1.0 - 0.5*0.30 = 0.85
    assert_in_delta 0.85, smile(retirement_age: 70).multiplier_for_age(75), 0.001
  end

  test 'curve adjusts when terminal age changes' do
    # With terminal_age=90, at age 85: t = 5/10 = 0.5
    expected = SpendingSmile::TROUGH_MULTIPLIER +
               0.5 * (SpendingSmile::TERMINAL_MULTIPLIER - SpendingSmile::TROUGH_MULTIPLIER)
    assert_in_delta expected, smile(terminal_age: 90).multiplier_for_age(85), 0.001
  end
end
