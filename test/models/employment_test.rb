# == Schema Information
#
# Table name: employments
#
#  id            :integer          not null, primary key
#  annual_income :integer          default(0), not null
#  currency_code :string           default("CAD"), not null
#  end_age       :integer          not null
#  label         :string
#  start_age     :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_employments_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require 'test_helper'

class EmploymentTest < ActiveSupport::TestCase
  def john_employment = employments(:john_employment)
  def bob_employment  = employments(:bob_employment)

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------

  test 'belongs to user' do
    assert_equal users(:working_user_john), john_employment.user
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  test 'valid with required attributes' do
    employment = Employment.new(
      user: users(:working_user_john),
      annual_income: 30_000,
      start_age: 65,
      end_age: 70,
      currency_code: 'CAD'
    )
    # Must use a user without an existing employment record
    employment.user = users(:onboarding_user)
    assert employment.valid?
  end

  test 'invalid without start_age' do
    john_employment.start_age = nil
    assert john_employment.invalid?
    assert_includes john_employment.errors[:start_age], "can't be blank"
  end

  test 'invalid without end_age' do
    john_employment.end_age = nil
    assert john_employment.invalid?
    assert_includes john_employment.errors[:end_age], "can't be blank"
  end

  test 'invalid when end_age is before start_age' do
    john_employment.end_age = john_employment.start_age - 1
    assert john_employment.invalid?
    assert john_employment.errors[:end_age].present?
  end

  test 'end_age equal to start_age is valid' do
    john_employment.end_age = john_employment.start_age
    assert john_employment.valid?
  end

  test 'invalid with negative annual_income' do
    john_employment.annual_income = -1
    assert john_employment.invalid?
    assert john_employment.errors[:annual_income].present?
  end

  test 'invalid without currency_code' do
    john_employment.currency_code = nil
    assert john_employment.invalid?
    assert_includes john_employment.errors[:currency_code], "can't be blank"
  end

  # ---------------------------------------------------------------------------
  # DB uniqueness - one record per user
  # ---------------------------------------------------------------------------

  test 'cannot create a second employment for the same user' do
    duplicate = Employment.new(
      user: users(:working_user_john),
      annual_income: 10_000,
      start_age: 68,
      end_age: 72,
      currency_code: 'CAD'
    )
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end

  # ---------------------------------------------------------------------------
  # income_in_year
  # ---------------------------------------------------------------------------

  test 'income_in_year returns annual_income when user age is within range' do
    # bob birth_date: 1950-01-01, retirement_age: 65 -> age 65 in 2015
    # bob_employment: start_age 65, end_age 72 -> active 2015-2022
    assert_equal 24_000, bob_employment.income_in_year(2018)
  end

  test 'income_in_year returns 0 before start_age' do
    # bob age 64 in 2014
    assert_equal 0, bob_employment.income_in_year(2014)
  end

  test 'income_in_year returns 0 after end_age' do
    # bob age 73 in 2023
    assert_equal 0, bob_employment.income_in_year(2023)
  end

  test 'income_in_year returns 0 when annual_income is 0' do
    assert_equal 0, john_employment.income_in_year(2050)
  end

  test 'income_in_year returns income on start_age boundary year' do
    # bob age 65 in 2015
    assert_equal 24_000, bob_employment.income_in_year(2015)
  end

  test 'income_in_year returns income on end_age boundary year' do
    # bob age 72 in 2022
    assert_equal 24_000, bob_employment.income_in_year(2022)
  end

  # ---------------------------------------------------------------------------
  # active_in_year?
  # ---------------------------------------------------------------------------

  test 'active_in_year? true when user age is within start/end range' do
    assert bob_employment.active_in_year?(2018)
  end

  test 'active_in_year? false before start_age' do
    assert_not bob_employment.active_in_year?(2014)
  end

  test 'active_in_year? false after end_age' do
    assert_not bob_employment.active_in_year?(2023)
  end

  test 'active_in_year? true on start_age boundary' do
    assert bob_employment.active_in_year?(2015)
  end

  test 'active_in_year? true on end_age boundary' do
    assert bob_employment.active_in_year?(2022)
  end
end
