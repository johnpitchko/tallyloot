require 'test_helper'

class Scenario::DraftTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'loads all household records' do
    draft = Scenario::Draft.from(@household)

    assert_equal 2, draft.users.size
    assert_equal 4, draft.accounts.size
    assert_equal 1, draft.pensions.size
    assert_equal 2, draft.benefits.size
    assert_equal 2, draft.employments.size
  end

  test 'record ids are intact' do
    draft = Scenario::Draft.from(@household)

    assert draft.accounts.all? { |a| a.id.present? }, 'account ids must survive loading'
    assert(draft.users.all? { |u| u.id.present? })
  end

  test 'account.user is the same object as the draft user' do
    draft = Scenario::Draft.from(@household)
    account = draft.accounts.first

    assert_same draft.user(account.user_id), account.user
  end

  test 'pension.user is the same object as the draft user' do
    draft = Scenario::Draft.from(@household)
    pension = draft.pensions.first

    assert_same draft.user(pension.user_id), pension.user
  end

  test 'household#terminal_year follows a mutated draft user' do
    draft = Scenario::Draft.from(@household)
    before = draft.household.terminal_year

    draft.users.each { |u| u.life_expectancy = 100 }

    assert_not_equal before, draft.household.terminal_year
    assert_equal draft.users.map(&:life_expectancy_year).max, draft.household.terminal_year
  end

  test 'household#retired_as_of? follows a mutated draft user' do
    draft = Scenario::Draft.from(@household)
    year = Time.zone.now.year + 5
    assert_not draft.household.retired_as_of?(year)

    draft.users.each { |u| u.retirement_age = 30 }

    assert draft.household.retired_as_of?(year)
  end

  test 'draft portfolio is not the caller portfolio object' do
    draft = Scenario::Draft.from(@household)

    assert_not_same @household.portfolio, draft.portfolio
  end

  test 'mutating the draft does not touch the database' do
    draft = Scenario::Draft.from(@household)
    draft.household.retirement_income_goal = 999_999
    draft.portfolio.glidepath_id = 12_345
    draft.users.each { |u| u.retirement_age = 40 }

    assert_equal 120_000, Household.find(@household.id).retirement_income_goal
    assert_equal 65, User.find(@john.id).retirement_age
  end

  test 'to_projection produces the same periods as the baseline' do
    baseline = Projection::Household.from_household(@household).periods
    drafted  = Scenario::Draft.from(@household).to_projection.periods

    assert_equal baseline.size, drafted.size
    assert_equal baseline.map(&:net_worth), drafted.map(&:net_worth)
  end

  test 'each account is tracked separately through the projection' do
    draft = Scenario::Draft.from(@household)
    periods = draft.to_projection.periods

    assert_equal 4, periods.first.account_periods.map(&:account_id).uniq.size
  end
end
