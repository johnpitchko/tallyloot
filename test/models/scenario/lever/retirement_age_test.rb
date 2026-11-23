require 'test_helper'

class Scenario::Lever::RetirementAgeTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'sets the retirement age on the target user only' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60).apply(draft)

    assert_equal 60, draft.user(@john.id).retirement_age
    assert_equal 65, draft.user(users(:working_user_jane).id).retirement_age
  end

  test 'changes the projection' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60).apply(draft)
    changed = draft.to_projection.periods

    assert_not_equal baseline.map(&:net_worth), changed.map(&:net_worth)
  end

  test 'describes itself with the person name' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)

    assert_equal 'John retires at age 60', lever.describe(draft)
  end

  test 'serialises to a hash' do
    lever = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)

    assert_equal({ 'lever' => 'retirement_age', 'person_id' => @john.id, 'value' => 60 }, lever.to_h)
  end

  test 'equality is by class, person and value' do
    a = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)
    b = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)
    c = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 61)

    assert_equal a, b
    assert_not_equal a, c
  end
end
