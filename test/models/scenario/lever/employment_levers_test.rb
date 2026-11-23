require 'test_helper'

class Scenario::Lever::EmploymentLeversTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'employment end age sets the end age' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::EmploymentEndAge.new(person_id: @john.id, value: 75).apply(draft)

    assert_equal 75, draft.user(@john.id).employment.end_age
  end

  test 'employment end age describes itself' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::EmploymentEndAge.new(person_id: @john.id, value: 75)

    assert_equal 'John works until age 75', lever.describe(draft)
  end

  test 'employment income sets the annual income' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::EmploymentIncome.new(person_id: @john.id, value: 30_000).apply(draft)

    assert_equal 30_000, draft.user(@john.id).employment.annual_income
  end

  test 'employment income changes the projection' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::EmploymentIncome.new(person_id: @john.id, value: 40_000).apply(draft)
    changed = draft.to_projection.periods

    assert_not_equal baseline.map(&:net_worth), changed.map(&:net_worth)
  end

  test 'employment income describes itself with currency formatting' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::EmploymentIncome.new(person_id: @john.id, value: 30_000)

    assert_equal 'John earns $30,000/yr in post-retirement work', lever.describe(draft)
  end
end
