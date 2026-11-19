require 'test_helper'

class SimulationTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)  # born 1980-01-01, retirement_age: 65
    @jane = users(:working_user_jane)  # born 1981-01-01, retirement_age: 65
  end

  # ─── No params ───────────────────────────────────────────────────────────────

  test 'no params: sim objects have same attribute values as originals' do
    sim = Simulation.new(@household, {})
    proj = sim.projection

    assert_equal @household.retirement_income_goal, proj.household.retirement_income_goal
    assert_equal @household.portfolio.glidepath_id, proj.portfolio.glidepath_id

    sim_john = proj.instance_variable_get(:@users).find { |u| u.id == @john.id }
    assert_equal @john.retirement_age, sim_john.retirement_age
    assert_equal @john.life_expectancy, sim_john.life_expectancy
  end

  test 'no params: projection produces periods' do
    periods = Simulation.new(@household, {}).projection.periods
    assert periods.any?, 'Expected at least one period'
    assert_kind_of Period::Summary, periods.first
  end

  # ─── Retirement income goal ───────────────────────────────────────────────────

  test 'overrides retirement income goal' do
    sim = Simulation.new(@household, { retirement_income_goal: '100000' })
    assert_equal 100_000, sim.projection.household.retirement_income_goal
  end

  test 'original household retirement income goal is unchanged' do
    Simulation.new(@household, { retirement_income_goal: '100000' }).projection
    assert_equal 120_000, @household.retirement_income_goal
  end

  # ─── Glidepath ───────────────────────────────────────────────────────────────

  test 'overrides glidepath' do
    other_glidepath = Glidepath.where.not(id: @household.portfolio.glidepath_id).first
    skip 'Need a second glidepath fixture' unless other_glidepath

    sim = Simulation.new(@household, { glidepath_id: other_glidepath.id.to_s })
    assert_equal other_glidepath.id, sim.projection.portfolio.glidepath_id
  end

  # ─── User retirement age ──────────────────────────────────────────────────────

  test 'overrides user retirement age' do
    params = { users: { @john.id.to_s => { retirement_age: '70' } } }
    sim = Simulation.new(@household, params)
    sim_john = sim.projection.instance_variable_get(:@users).find { |u| u.id == @john.id }
    assert_equal 70, sim_john.retirement_age
  end

  test 'original user retirement age is unchanged after sim' do
    params = { users: { @john.id.to_s => { retirement_age: '70' } } }
    Simulation.new(@household, params).projection
    assert_equal 65, @john.reload.retirement_age
  end

  test 'overriding one user retirement age does not affect the other user' do
    params = { users: { @john.id.to_s => { retirement_age: '70' } } }
    sim = Simulation.new(@household, params)
    sim_jane = sim.projection.instance_variable_get(:@users).find { |u| u.id == @jane.id }
    assert_equal @jane.retirement_age, sim_jane.retirement_age
  end

  # ─── User life expectancy ─────────────────────────────────────────────────────

  test 'overrides user life expectancy' do
    params = { users: { @john.id.to_s => { life_expectancy: '90' } } }
    sim = Simulation.new(@household, params)
    sim_john = sim.projection.instance_variable_get(:@users).find { |u| u.id == @john.id }
    assert_equal 90, sim_john.life_expectancy
  end

  # ─── Account contribution ─────────────────────────────────────────────────────

  test 'overrides account contribution' do
    account = accounts(:rrsp_john)
    params = { accounts: { account.id.to_s => { contribution: '20000' } } }
    sim = Simulation.new(@household, params)
    sim_account = sim.projection.instance_variable_get(:@accounts).find { |a| a.id == account.id }
    assert_equal 20_000, sim_account.contribution
  end

  test 'original account contribution is unchanged after sim' do
    account = accounts(:rrsp_john)
    original_contribution = account.contribution
    params = { accounts: { account.id.to_s => { contribution: '20000' } } }
    Simulation.new(@household, params).projection
    assert_equal original_contribution, account.reload.contribution
  end

  # ─── Pension start age ────────────────────────────────────────────────────────

  test 'overrides pension start age' do
    pension = pensions(:indexed)  # start_age: 65, user: working_user_john (born 1980)
    params = { pensions: { pension.id.to_s => { start_age: '60' } } }
    sim = Simulation.new(@household, params)
    sim_pension = sim.projection.instance_variable_get(:@pensions).find { |p| p.id == pension.id }
    assert_equal 60, sim_pension.start_age
  end

  test 'dup pension start_year resolves via sim user birth_date without DB hit' do
    pension = pensions(:indexed)  # start_age: 65, user: working_user_john (born 1980) → start_year 2045
    params = { pensions: { pension.id.to_s => { start_age: '60' } } }
    sim = Simulation.new(@household, params)
    sim_pension = sim.projection.instance_variable_get(:@pensions).find { |p| p.id == pension.id }

    # start_year should be birth_year (1980) + start_age (60) = 2040
    assert_equal 2040, sim_pension.start_year,
                 'Sim pension start_year should use sim user birth_year + overridden start_age'
  end

  test 'original pension start age is unchanged after sim' do
    pension = pensions(:indexed)
    params = { pensions: { pension.id.to_s => { start_age: '60' } } }
    Simulation.new(@household, params).projection
    assert_equal 65, pension.reload.start_age
  end

  # ─── Benefit start age ────────────────────────────────────────────────────────

  test 'overrides benefit start age' do
    benefit = benefits(:cpp_john)  # start_age: 65
    params = { benefits: { benefit.id.to_s => { start_age: '70' } } }
    sim = Simulation.new(@household, params)
    sim_benefit = sim.projection.instance_variable_get(:@benefits).find { |b| b.id == benefit.id }
    assert_equal 70, sim_benefit.start_age
  end

  test 'dup benefit start_year resolves via sim user without DB hit' do
    benefit = benefits(:cpp_john)  # start_age: 65, user: working_user_john (born 1980) → start_year 2045
    params = { benefits: { benefit.id.to_s => { start_age: '70' } } }
    sim = Simulation.new(@household, params)
    sim_benefit = sim.projection.instance_variable_get(:@benefits).find { |b| b.id == benefit.id }

    # start_year should be birth_year (1980) + start_age (70) = 2050
    assert_equal 2050, sim_benefit.start_year,
                 'Sim benefit start_year should use sim user birth_year + overridden start_age'
  end

  test 'benefit income_eligible? uses sim user birth_date' do
    benefit = benefits(:cpp_john)  # start_age: 65 → income eligible from 2045
    params = { benefits: { benefit.id.to_s => { start_age: '70' } } }
    sim = Simulation.new(@household, params)
    sim_benefit = sim.projection.instance_variable_get(:@benefits).find { |b| b.id == benefit.id }

    # With start_age 70 (start_year 2050), should NOT be eligible in 2045
    assert_not sim_benefit.income_eligible?(2045),
               'Sim benefit with start_age 70 should not be eligible in 2045'
    # But should be eligible from 2050
    assert sim_benefit.income_eligible?(2050),
           'Sim benefit with start_age 70 should be eligible in 2050'
  end

  # ─── Regression: delayed retirement age produces higher peak net worth ────────

  test 'delaying retirement age produces higher or equal peak net worth' do
    # Current projection: John retires at 65 (1980+65=2045), Jane at 65 (1981+65=2046)
    current_periods = Projection::Household.from_household(@household).periods
    current_peak = current_periods.map(&:net_worth).max

    # Simulated: John retires at 75 (1980+75=2055) — 10 more accumulation years
    params = { users: { @john.id.to_s => { retirement_age: '75' } } }
    sim_periods = Simulation.new(@household, params).projection.periods
    sim_peak = sim_periods.map(&:net_worth).max

    assert sim_peak >= current_peak,
           "Delaying retirement should increase peak net worth. " \
           "Current peak: #{current_peak}, Simulated peak: #{sim_peak}"
  end
end
