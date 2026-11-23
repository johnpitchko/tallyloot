# == Schema Information
#
# Table name: scenarios
#
#  id                  :integer          not null, primary key
#  clarifying_question :text
#  confirmed_at        :datetime
#  confirmed_levers    :json             not null
#  parsed_levers       :json             not null
#  raw_input           :text             not null
#  status              :string           default("parsed"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  household_id        :integer          not null
#
# Indexes
#
#  index_scenarios_on_household_id  (household_id)
#  index_scenarios_on_status        (status)
#
# Foreign Keys
#
#  household_id  (household_id => households.id)
#
require 'test_helper'

class ScenarioTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
  end

  test 'requires raw_input' do
    scenario = Scenario.new(household: @household)
    assert_not scenario.valid?
    assert_includes scenario.errors[:raw_input], "can't be blank"
  end

  test 'rejects raw_input longer than 500 characters' do
    scenario = Scenario.new(household: @household, raw_input: 'a' * 501)
    assert_not scenario.valid?
    assert_includes scenario.errors[:raw_input], 'is too long (maximum is 500 characters)'
  end

  test 'accepts raw_input at exactly 500 characters' do
    scenario = Scenario.new(household: @household, raw_input: 'a' * 500)
    assert scenario.valid?
  end

  test 'defaults to parsed status' do
    scenario = Scenario.create!(household: @household, raw_input: 'retire at 60')
    assert scenario.parsed?
  end

  test 'confirm! records the levers and timestamp' do
    scenario = Scenario.create!(household: @household, raw_input: 'retire at 60')
    levers = [{ 'lever' => 'retirement_age', 'person_id' => 1, 'value' => 60 }]

    scenario.confirm!(levers)

    assert scenario.confirmed?
    assert_equal levers, scenario.confirmed_levers
    assert_not_nil scenario.confirmed_at
  end

  test 'destroying a household destroys its scenarios' do
    household = Household.create!
    Scenario.create!(household: household, raw_input: 'retire at 60')

    assert_difference 'Scenario.count', -1 do
      household.destroy
    end
  end
end
