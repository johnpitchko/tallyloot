require 'test_helper'

class SampleHouseholdTest < ActiveSupport::TestCase
  test 'creates a ready-to-project household flagged as sample data' do
    household = SampleHousehold.create!

    assert household.sample_data?
    assert_equal 1, household.users.count
    assert_not_nil household.portfolio
    assert household.accounts.any?
    assert household.benefits.any?
    assert Projection::Household.from_household(household).periods.any?
  end
end
