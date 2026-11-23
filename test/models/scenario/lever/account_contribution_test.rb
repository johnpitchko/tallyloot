require 'test_helper'

class Scenario::Lever::AccountContributionTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @tfsa = accounts(:tfsa_john)
  end

  test 'sets the contribution on the target account only' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000).apply(draft)

    target = draft.accounts.find { |a| a.id == @tfsa.id }
    others = draft.accounts.reject { |a| a.id == @tfsa.id }

    assert_equal 6000, target.contribution
    assert others.all? { |a| a.contribution.zero? }
  end

  test 'changes the projection' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000).apply(draft)

    assert_not_equal baseline.map(&:net_worth), draft.to_projection.periods.map(&:net_worth)
  end

  test 'describes itself with the account name' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000)

    assert_equal 'Contribute $6,000/yr to TFSA', lever.describe(draft)
  end

  test 'serialises with account_id' do
    lever = Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000)

    assert_equal(
      { 'lever' => 'account_contribution', 'person_id' => nil, 'account_id' => @tfsa.id, 'value' => 6000 },
      lever.to_h
    )
  end
end
