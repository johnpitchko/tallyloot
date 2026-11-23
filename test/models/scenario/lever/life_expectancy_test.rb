require 'test_helper'

class Scenario::Lever::LifeExpectancyTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'sets the life expectancy on the target user' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::LifeExpectancy.new(person_id: @john.id, value: 95).apply(draft)

    assert_equal 95, draft.user(@john.id).life_expectancy
  end

  test 'extends the projection terminal year' do
    draft = Scenario::Draft.from(@household)
    before = draft.to_projection.periods.size

    Scenario::Lever::LifeExpectancy.new(person_id: @john.id, value: 95).apply(draft)

    assert_operator draft.to_projection.periods.size, :>, before
  end

  test 'describes itself with the person name' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::LifeExpectancy.new(person_id: @john.id, value: 95)

    assert_equal 'John lives to age 95', lever.describe(draft)
  end
end
