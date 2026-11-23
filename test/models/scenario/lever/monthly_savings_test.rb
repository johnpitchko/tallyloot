require 'test_helper'

class Scenario::Lever::MonthlySavingsTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'spreads the annualised delta across all accounts when none contribute' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 200).apply(draft)

    johns = draft.accounts.select { |a| a.user_id == @john.id }
    assert_equal 2, johns.size
    assert_equal [1200, 1200], johns.map(&:contribution).sort
  end

  test 'only targets accounts that already contribute when some do' do
    draft = Scenario::Draft.from(@household)
    tfsa = draft.accounts.find { |a| a.id == accounts(:tfsa_john).id }
    tfsa.contribution = 1000

    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 100).apply(draft)

    rrsp = draft.accounts.find { |a| a.id == accounts(:rrsp_john).id }
    assert_equal 2200, tfsa.contribution
    assert_equal 0, rrsp.contribution
  end

  test 'does not touch the other household member' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 200).apply(draft)

    janes = draft.accounts.select { |a| a.user_id == users(:working_user_jane).id }
    assert janes.all? { |a| a.contribution.zero? }
  end

  test 'floors contributions at zero for a negative delta' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: -500).apply(draft)

    johns = draft.accounts.select { |a| a.user_id == @john.id }
    assert johns.all? { |a| a.contribution >= 0 }
  end

  test 'increases projected net worth' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 500).apply(draft)

    assert_operator draft.to_projection.periods.map(&:net_worth).max, :>, baseline.map(&:net_worth).max
  end

  test 'describes itself' do
    draft = Scenario::Draft.from(@household)

    assert_equal 'John saves $500/mo more',
                 Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 500).describe(draft)
    assert_equal 'John saves $300/mo less',
                 Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: -300).describe(draft)
  end
end
