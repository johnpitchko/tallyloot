require 'test_helper'

class ChartRoundingTest < ActiveSupport::TestCase
  test 'rounds down to the nearest thousand' do
    assert_equal 150_000, ChartRounding.round_to_nearest_thousand(150_001)
    assert_equal 347_000, ChartRounding.round_to_nearest_thousand(347_231)
  end

  test 'rounds up to the nearest thousand' do
    assert_equal 150_000, ChartRounding.round_to_nearest_thousand(149_999)
    assert_equal 348_000, ChartRounding.round_to_nearest_thousand(347_500)
  end

  test 'leaves exact thousands unchanged' do
    assert_equal 150_000, ChartRounding.round_to_nearest_thousand(150_000)
    assert_equal 0, ChartRounding.round_to_nearest_thousand(0)
  end

  test 'passes nil through' do
    assert_nil ChartRounding.round_to_nearest_thousand(nil)
  end

  test 'round_series rounds every element to the nearest thousand' do
    assert_equal [150_000, 347_000, nil], ChartRounding.round_series([149_999, 347_231, nil])
  end
end
