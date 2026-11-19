# == Schema Information
#
# Table name: glidepaths
#
#  id          :integer          not null, primary key
#  description :text
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_glidepaths_on_name  (name) UNIQUE
#
require 'test_helper'

class GlidepathTest < ActiveSupport::TestCase
  setup do
    @glidepath = glidepaths(:standard_retirement)
    @empty_glidepath = glidepaths(:empty_glidepath)

    @very_aggressive = allocations(:very_aggressive)
    @aggressive = allocations(:aggressive)
    @balanced = allocations(:balanced)
    @conservative = allocations(:conservative)
    @very_conservative = allocations(:very_conservative)
  end

  test 'nominal_return_for_age returns correct return for age' do
    assert_equal @very_aggressive.avg_nominal_return, @glidepath.nominal_return_for_age(25)
    assert_equal @aggressive.avg_nominal_return, @glidepath.nominal_return_for_age(45)
    assert_equal @balanced.avg_nominal_return, @glidepath.nominal_return_for_age(65)
    assert_equal @balanced.avg_nominal_return, @glidepath.nominal_return_for_age(85)
  end

  test 'allocation_for_age returns correct allocation for exact start_age match' do
    assert_equal @very_aggressive, @glidepath.allocation_for_age(25)
    assert_equal @aggressive, @glidepath.allocation_for_age(45)
    assert_equal @balanced, @glidepath.allocation_for_age(65)
  end

  test 'allocation_for_age returns most recent allocation for in-between ages' do
    assert_equal @aggressive, @glidepath.allocation_for_age(50)
    assert_equal @balanced, @glidepath.allocation_for_age(70)
  end

  test 'allocation_for_age raises error when age is younger than any step' do
    assert_raises RuntimeError do
      @glidepath.allocation_for_age(20)
    end
  end

  test 'allocation_for_age raises error when there are no steps' do
    assert_raises RuntimeError do
      @empty_glidepath.allocation_for_age(30)
    end
  end

  test ".default returns the glidepath named 'Standard Retirement'" do
    assert_equal @glidepath, Glidepath.default
  end
end
