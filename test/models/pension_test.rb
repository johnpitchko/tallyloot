# == Schema Information
#
# Table name: pensions
#
#  id                    :integer          not null, primary key
#  annual_amount         :decimal(10, 2)   default(0.0), not null
#  description           :string
#  early_reduction_rate  :decimal(5, 4)
#  inflation_indexed     :boolean
#  late_increase_rate    :decimal(5, 4)
#  name                  :string
#  normal_retirement_age :integer          default(65)
#  start_age             :integer          not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  user_id               :integer          not null
#
# Indexes
#
#  index_pensions_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require 'test_helper'

class PensionTest < ActiveSupport::TestCase
  setup do
    @indexed = pensions(:indexed)
    @non_indexed = pensions(:non_indexed)
  end

  test 'pension income eligibility' do
    assert_not(@indexed.income_eligible?(2030), 'Pension should not be eligible for income in 2030')
    assert(@indexed.income_eligible?(2050), 'Pension should be eligible for income in 2050')
  end

  test 'start age calculation' do
    assert_equal 65, @indexed.start_age, 'Start age should be 65 for indexed pension'
    assert_equal 2045, @indexed.start_year, 'Start year should be 2045 for indexed pension (born 1980 + age 65)'
  end

  test 'annual amount nominal for indexed pension' do
    assert_equal 7000, @indexed.annual_amount_nominal(2045),
                 'Annual amount nominal for indexed pension should be 7000 in 2045'
    assert_equal 0, @indexed.annual_amount_nominal(2030),
                 'Annual amount nominal for indexed pension should be 0 in 2030'

    inflation_rate = 0.025
    pension_amount_in_10_years = (7000 * ((1 + inflation_rate)**10)).round
    assert_equal pension_amount_in_10_years, @indexed.annual_amount_nominal(2055, inflation_rate:),
                 'Annual amount nominal for indexed pension should be adjusted for inflation in 2055'
  end
end
