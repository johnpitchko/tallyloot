# == Schema Information
#
# Table name: benefits
#
#  id                :integer          not null, primary key
#  annual_amount     :integer
#  inflation_indexed :boolean
#  name              :string
#  start_age         :integer
#  type              :string           default("Benefit::Custom"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :integer          not null
#
# Indexes
#
#  index_benefits_on_type     (type)
#  index_benefits_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require 'test_helper'

class BenefitTest < ActiveSupport::TestCase
  setup do
    @user = users(:working_user_john)
  end

  test 'CPP benefit returns correct type_name' do
    cpp = Benefit::Cpp.new(user: @user, name: 'CPP', annual_amount: 15_000, start_age: 65)
    assert_equal 'CPP', cpp.type_name
  end

  test 'OAS benefit returns correct type_name' do
    oas = Benefit::Oas.new(user: @user, name: 'OAS', annual_amount: 8500, start_age: 65)
    assert_equal 'OAS', oas.type_name
  end

  test 'Custom benefit returns correct type_name' do
    custom = Benefit::Custom.new(user: @user, name: 'Annuity', annual_amount: 5000, start_age: 60)
    assert_equal 'Other Benefit', custom.type_name
  end

  test 'CPP is always inflation indexed' do
    cpp = Benefit::Cpp.new(user: @user, name: 'CPP', annual_amount: 15_000, start_age: 65, inflation_indexed: false)
    assert cpp.inflation_indexed?
  end

  test 'OAS is always inflation indexed' do
    oas = Benefit::Oas.new(user: @user, name: 'OAS', annual_amount: 8500, start_age: 65, inflation_indexed: false)
    assert oas.inflation_indexed?
  end

  test 'Custom benefit respects inflation_indexed setting' do
    indexed = Benefit::Custom.new(user: @user, name: 'Test', annual_amount: 5000, start_age: 60,
                                  inflation_indexed: true)
    not_indexed = Benefit::Custom.new(user: @user, name: 'Test', annual_amount: 5000, start_age: 60,
                                      inflation_indexed: false)

    assert indexed.inflation_indexed?
    assert_not not_indexed.inflation_indexed?
  end

  test 'CPP and OAS are government benefits' do
    cpp = Benefit::Cpp.new(user: @user, name: 'CPP', annual_amount: 15_000, start_age: 65)
    oas = Benefit::Oas.new(user: @user, name: 'OAS', annual_amount: 8500, start_age: 65)
    custom = Benefit::Custom.new(user: @user, name: 'Test', annual_amount: 5000, start_age: 60)

    assert cpp.government_benefit?
    assert oas.government_benefit?
    assert_not custom.government_benefit?
  end

  test 'CPP validates start age between 60 and 70' do
    cpp = Benefit::Cpp.new(user: @user, name: 'CPP', annual_amount: 15_000, start_age: 59)
    assert_not cpp.valid?
    assert_includes cpp.errors[:start_age], 'must be greater than or equal to 60'

    cpp.start_age = 71
    assert_not cpp.valid?
    assert_includes cpp.errors[:start_age], 'must be less than or equal to 70'

    cpp.start_age = 65
    assert cpp.valid?
  end

  test 'OAS validates start age between 65 and 70' do
    oas = Benefit::Oas.new(user: @user, name: 'OAS', annual_amount: 8500, start_age: 64)
    assert_not oas.valid?
    assert_includes oas.errors[:start_age], 'must be greater than or equal to 65'

    oas.start_age = 71
    assert_not oas.valid?
    assert_includes oas.errors[:start_age], 'must be less than or equal to 70'

    oas.start_age = 67
    assert oas.valid?
  end

  test 'CPP early start reduces benefit' do
    cpp = Benefit::Cpp.new(user: @user, name: 'CPP', annual_amount: 15_000, start_age: 60)

    # 5 years early = 60 months * 0.6% = 36% reduction
    expected_factor = 1.0 - (60 * 0.006)
    assert_in_delta expected_factor, cpp.adjustment_factor, 0.001
    assert_equal (15_000 * expected_factor).round, cpp.adjusted_annual_amount
  end

  test 'CPP late start increases benefit' do
    cpp = Benefit::Cpp.new(user: @user, name: 'CPP', annual_amount: 15_000, start_age: 70)

    # 5 years late = 60 months * 0.7% = 42% increase
    expected_factor = 1.0 + (60 * 0.007)
    assert_in_delta expected_factor, cpp.adjustment_factor, 0.001
    assert_equal (15_000 * expected_factor).round, cpp.adjusted_annual_amount
  end

  test 'CPP at standard age has no adjustment' do
    cpp = Benefit::Cpp.new(user: @user, name: 'CPP', annual_amount: 15_000, start_age: 65)

    assert_in_delta 1.0, cpp.adjustment_factor, 0.001
    assert_equal 15_000, cpp.adjusted_annual_amount
  end

  test 'OAS delayed start increases benefit' do
    oas = Benefit::Oas.new(user: @user, name: 'OAS', annual_amount: 8500, start_age: 70)

    # 5 years delay = 60 months * 0.6% = 36% increase
    expected_factor = 1.0 + (60 * 0.006)
    assert_in_delta expected_factor, oas.adjustment_factor, 0.001
    assert_equal (8500 * expected_factor).round, oas.adjusted_annual_amount
  end

  test 'OAS at standard age has no adjustment' do
    oas = Benefit::Oas.new(user: @user, name: 'OAS', annual_amount: 8500, start_age: 65)

    assert_in_delta 1.0, oas.adjustment_factor, 0.001
    assert_equal 8500, oas.adjusted_annual_amount
  end

  test 'type_options returns all benefit types' do
    options = Benefit.type_options

    assert_equal 3, options.length
    assert_includes options, ['CPP', 'Benefit::Cpp']
    assert_includes options, ['OAS', 'Benefit::Oas']
    assert_includes options, ['Other Benefit', 'Benefit::Custom']
  end
end
