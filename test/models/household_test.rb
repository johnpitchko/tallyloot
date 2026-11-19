# == Schema Information
#
# Table name: households
#
#  id                     :integer          not null, primary key
#  province               :string
#  retirement_income_goal :integer
#  sample_data            :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
require 'test_helper'

class HouseholdTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
  end

  test 'should have a valid household' do
    assert @household.valid?, 'Household should be valid'
  end

  test 'should calculate max life expectancy year' do
    assert_equal 2063, @household.max_life_expectancy_year, 'Max life expectancy year should be 2063 (Jane: 1981 + 82)'
  end

  test 'calculate if anyone in the household retires in a given year' do
    assert @household.retired_as_of?(2060), 'Someone should retire in 2060'
    assert_not @household.retired_as_of?(2025), 'No one should retire in 2025'
  end

  test 'fully_retired_year is the latest member retirement year' do
    # John: 1980 + 65 = 2045, Jane: 1981 + 65 = 2046
    assert_equal 2046, @household.fully_retired_year, 'Should be the year the last member retires (Jane, 2046)'
  end

  test 'fully_retired_as_of? is true only once every member is retired' do
    # In 2045 John is retired but Jane is not, so the household is not fully retired.
    assert @household.retired_as_of?(2045), 'John has retired by 2045'
    assert_not @household.fully_retired_as_of?(2045), 'Jane still works in 2045, so not fully retired'
    assert @household.fully_retired_as_of?(2046), 'Both members are retired by 2046'
  end

  # test 'return age of the eldest user in the household' do
  #   assert_equal 45, @household.age(2025), 'Eldest user should be 40 years old in 2025'
  #   assert_equal 55, @household.age(2035), 'Eldest user should be 50 years old in 2035'
  # end

  test 'should return milestone years based on eldest user' do
    expected_years = [Time.zone.now.year, 2035, 2040, 2045, 2050, 2055, 2060, 2065]
    assert_equal expected_years, @household.milestone_years, 'Milestone years should match expected values'
  end
end
