require 'test_helper'

class WhatIfsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:working_user_john)
    @household = households(:non_retired)
  end

  def sign_in(user = @user)
    act_as(user)
  end

  def extract_chart_data(css_selector)
    node = css_select(css_selector).first
    return nil unless node

    JSON.parse(node['data-simulation-chart-chart-data-value'], symbolize_names: true)
  end

  # ─── Default (no params) ─────────────────────────────────────────────────────

  test 'GET /what_if with no params returns 200' do
    sign_in
    get what_if_path
    assert_response :success
  end

  test 'no params: current and what-if net worth are identical' do
    sign_in
    get what_if_path
    data = extract_chart_data('#what_if_net_worth_chart')
    assert_not_nil data
    assert_equal data[:current], data[:simulated]
  end

  test 'no params: chart labels and value arrays are the same length' do
    sign_in
    get what_if_path
    data = extract_chart_data('#what_if_net_worth_chart')
    assert_equal data[:labels].length, data[:current].length
    assert_equal data[:labels].length, data[:simulated].length
  end

  # ─── Page structure ───────────────────────────────────────────────────────────

  test 'levers form targets the what_if_results turbo frame' do
    sign_in
    get what_if_path
    assert_select "form[data-turbo-frame='what_if_results']"
  end

  test 'turbo frame wrapper is present around results' do
    sign_in
    get what_if_path
    assert_select 'turbo-frame#what_if_results'
  end

  test 'net worth chart element is present' do
    sign_in
    get what_if_path
    assert_select '#what_if_net_worth_chart[data-simulation-chart-chart-data-value]'
  end

  test 'income chart element is present' do
    sign_in
    get what_if_path
    assert_select '#what_if_income_chart[data-simulation-chart-chart-data-value]'
  end

  test 'income chart values are rounded to the nearest $1,000' do
    sign_in
    get what_if_path
    data = extract_chart_data('#what_if_income_chart')

    %i[current simulated current_real simulated_real income_goal income_goal_real].each do |key|
      values = data[key].compact
      assert(values.all? { |v| (v % 1000).zero? }, "#{key} should be multiples of 1000: #{values.inspect}")
    end
  end

  test 'retirement age lever renders a select for each household user' do
    sign_in
    get what_if_path
    @household.users.each do |user|
      assert_select "select[name='users[#{user.id}][retirement_age]']"
    end
  end

  test 'CPP and OAS appear side-by-side with landmark ages only' do
    sign_in
    get what_if_path
    cpp = benefits(:cpp_john)
    oas = benefits(:oas_john)
    assert_select "#what_if_benefit_#{cpp.id}"
    assert_select "#what_if_benefit_#{oas.id}"
    assert_select "select[name='benefits[#{cpp.id}][start_age]'] option", count: 3  # 60, 65, 70
    assert_select "select[name='benefits[#{oas.id}][start_age]'] option", count: 2  # 65, 70
  end

  test 'warning shown when benefit start age is before retirement age' do
    sign_in
    cpp = benefits(:cpp_john)
    # John retires at 65 (default); CPP at 60 is before retirement
    get what_if_path, params: {
      users: { @user.id.to_s => { retirement_age: '65' } },
      benefits: { cpp.id.to_s => { start_age: '60' } },
    }
    assert_select '#what_if_age_warnings'
    assert_select '#what_if_net_worth_chart'  # chart still renders (shows current plan)
  end

  test 'no warning when benefit start age matches retirement age' do
    sign_in
    cpp = benefits(:cpp_john)
    get what_if_path, params: {
      users: { @user.id.to_s => { retirement_age: '65' } },
      benefits: { cpp.id.to_s => { start_age: '65' } },
    }
    assert_select '#what_if_age_warnings', count: 0
  end

  test 'monthly savings lever is present per user' do
    sign_in
    get what_if_path
    @household.users.each do |user|
      assert_select "#what_if_monthly_savings_#{user.id}"
      assert_select "input[name='users[#{user.id}][monthly_savings_delta]']"
    end
  end

  test 'glidepath lever is not present on What If page' do
    sign_in
    get what_if_path
    assert_select "select[name='glidepath_id']", count: 0
  end

  test 'reset link points to bare what_if path with full-page navigation' do
    sign_in
    get what_if_path
    assert_select "a[href='#{what_if_path}'][data-turbo-frame='_top']", text: 'Reset'
  end

  test 'summary cards are present' do
    sign_in
    get what_if_path
    assert_select '#what_if_peak_net_worth_card'
    assert_select '#what_if_avg_income_card'
  end

  # ─── Lever: retirement age ────────────────────────────────────────────────────

  test 'changing retirement age renders successfully' do
    sign_in
    get what_if_path, params: { users: { @user.id.to_s => { retirement_age: '70' } } }
    assert_response :success
  end

  test 'delaying retirement age produces higher or equal peak net worth' do
    sign_in

    get what_if_path
    baseline = extract_chart_data('#what_if_net_worth_chart')[:current].max

    get what_if_path, params: { users: { @user.id.to_s => { retirement_age: '70' } } }
    what_if_peak = extract_chart_data('#what_if_net_worth_chart')[:simulated].max

    assert what_if_peak >= baseline,
           "Delaying retirement should produce higher or equal peak net worth. " \
           "Baseline: #{baseline}, What-if: #{what_if_peak}"
  end

  test 'retirement age lever pre-selects the param value when present' do
    sign_in
    get what_if_path, params: { users: { @user.id.to_s => { retirement_age: '70' } } }
    assert_select "select[name='users[#{@user.id}][retirement_age]'] option[value='70'][selected]"
  end

  # ─── Lever: monthly savings ───────────────────────────────────────────────────

  test 'positive monthly savings delta renders successfully' do
    sign_in
    get what_if_path, params: { users: { @user.id.to_s => { monthly_savings_delta: '500' } } }
    assert_response :success
  end

  test 'positive monthly savings delta produces higher what-if net worth' do
    sign_in

    get what_if_path
    baseline_peak = extract_chart_data('#what_if_net_worth_chart')[:current].max

    get what_if_path, params: { users: { @user.id.to_s => { monthly_savings_delta: '1000' } } }
    what_if_peak = extract_chart_data('#what_if_net_worth_chart')[:simulated].max

    assert what_if_peak >= baseline_peak,
           "Increasing monthly savings should produce higher or equal peak net worth. " \
           "Baseline: #{baseline_peak}, What-if: #{what_if_peak}"
  end

  # ─── Lever: CPP / OAS start age ───────────────────────────────────────────────

  test 'changing CPP start age renders successfully' do
    sign_in
    cpp = benefits(:cpp_john)
    get what_if_path, params: { benefits: { cpp.id.to_s => { start_age: '70' } } }
    assert_response :success
  end

  test 'changing OAS start age renders successfully' do
    sign_in
    oas = benefits(:oas_john)
    get what_if_path, params: { benefits: { oas.id.to_s => { start_age: '70' } } }
    assert_response :success
  end

  test 'delaying CPP start age renders successfully' do
    sign_in
    cpp = benefits(:cpp_john)
    get what_if_path, params: { benefits: { cpp.id.to_s => { start_age: '70' } } }
    assert_response :success
  end

  test 'delaying OAS start age renders successfully' do
    sign_in
    oas = benefits(:oas_john)
    get what_if_path, params: { benefits: { oas.id.to_s => { start_age: '70' } } }
    assert_response :success
  end

  # ─── Lever: pension start age ─────────────────────────────────────────────────

  test 'pension start age lever is present for users with pensions' do
    sign_in
    get what_if_path
    assert_select "#what_if_pension_start_age_#{@user.id}"
    assert_select "select[name='users[#{@user.id}][pension_start_age]']"
  end

  test 'changing pension start age renders successfully' do
    sign_in
    get what_if_path, params: { users: { @user.id.to_s => { pension_start_age: '60' } } }
    assert_response :success
  end

  test 'pension start age lever pre-selects the param value when present' do
    sign_in
    get what_if_path, params: { users: { @user.id.to_s => { pension_start_age: '70' } } }
    assert_select "select[name='users[#{@user.id}][pension_start_age]'] option[value='70'][selected]"
  end

  test 'no insights shown when benefit start age matches plan' do
    sign_in
    cpp = benefits(:cpp_john)
    get what_if_path, params: { benefits: { cpp.id.to_s => { start_age: cpp.start_age.to_s } } }
    assert_select '#what_if_insights', count: 0
  end

end
