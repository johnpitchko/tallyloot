require 'test_helper'

class SimulatorsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:working_user_john)
    @household = households(:non_retired)
  end

  def sign_in(user = @user)
    act_as(user)
  end

  # Extracts chart data JSON embedded in the page as a data attribute.
  # Returns a hash with symbolized keys, e.g. { labels:, current:, simulated: }
  def extract_chart_data(css_selector)
    node = css_select(css_selector).first
    return nil unless node

    JSON.parse(node['data-simulation-chart-chart-data-value'], symbolize_names: true)
  end

  # ─── No sim params ────────────────────────────────────────────────────────────

  test 'GET /simulation with no params returns 200' do
    sign_in
    get simulator_path
    assert_response :success
  end

  test 'no sim params: current and simulated net worth are identical' do
    sign_in
    get simulator_path
    data = extract_chart_data('#net_worth_simulation_chart')
    assert_not_nil data
    assert_equal data[:current], data[:simulated]
  end

  test 'no sim params: chart has labels and value arrays of the same length' do
    sign_in
    get simulator_path
    data = extract_chart_data('#net_worth_simulation_chart')
    assert_not_nil data
    assert_equal data[:labels].length, data[:current].length
    assert_equal data[:labels].length, data[:simulated].length
  end

  test 'no sim params: net worth breakdown table is present' do
    sign_in
    get simulator_path
    assert_select 'details#net_worth_breakdown'
    assert_select 'details#income_breakdown'
  end

  test 'no sim params: net worth breakdown rows have zero delta' do
    sign_in
    get simulator_path
    # All delta cells should show $0 when current == simulated
    assert_select 'tr[id^="net_worth_row_"]' do |rows|
      assert rows.any?, 'Expected at least one net worth breakdown row'
    end
  end

  # ─── With sim params ──────────────────────────────────────────────────────────

  test 'retirement income goal override renders successfully' do
    sign_in
    get simulator_path, params: { retirement_income_goal: '200000' }
    assert_response :success
  end

  test 'user retirement age override renders successfully' do
    sign_in
    get simulator_path, params: { users: { @user.id.to_s => { retirement_age: '75' } } }
    assert_response :success
  end

  test 'delaying retirement age produces higher peak simulated net worth' do
    sign_in

    # Get current projection net worth values
    get simulator_path
    current_data = extract_chart_data('#net_worth_simulation_chart')
    current_peak = current_data[:current].max

    # Get simulated projection with later retirement
    get simulator_path, params: { users: { @user.id.to_s => { retirement_age: '75' } } }
    sim_data = extract_chart_data('#net_worth_simulation_chart')
    simulated_peak = sim_data[:simulated].max

    assert simulated_peak >= current_peak,
           "Delaying retirement should produce higher or equal peak net worth. " \
           "Current peak: #{current_peak}, Simulated peak: #{simulated_peak}"
  end

  test 'sim params produce different current and simulated lines' do
    sign_in
    get simulator_path, params: { users: { @user.id.to_s => { retirement_age: '75' } } }
    data = extract_chart_data('#net_worth_simulation_chart')
    assert data[:current] != data[:simulated],
           'Expected current and simulated lines to differ when retirement age changes'
  end

  test 'income goal sim param produces different simulated income' do
    sign_in
    get simulator_path, params: { retirement_income_goal: '200000' }
    data = extract_chart_data('#income_simulation_chart')
    assert_not_nil data
  end

  # ─── Response structure ───────────────────────────────────────────────────────

  test 'net worth chart element is present' do
    sign_in
    get simulator_path
    assert_select '#net_worth_simulation_chart[data-simulation-chart-chart-data-value]'
  end

  test 'income chart element is present' do
    sign_in
    get simulator_path
    assert_select '#income_simulation_chart[data-simulation-chart-chart-data-value]'
  end

  test 'income chart values are rounded to the nearest $1,000' do
    sign_in
    get simulator_path
    data = extract_chart_data('#income_simulation_chart')

    series = %i[current simulated current_real simulated_real income_goal income_goal_real]
    series.each do |key|
      values = data[key].compact
      assert(values.all? { |v| (v % 1000).zero? }, "#{key} should be multiples of 1000: #{values.inspect}")
    end

    data[:per_user].each do |user_series|
      %i[current simulated current_real simulated_real].each do |key|
        values = user_series[key].compact
        assert(values.all? { |v| (v % 1000).zero? }, "per_user #{key} should be multiples of 1000: #{values.inspect}")
      end
    end
  end

  test 'income breakdown table is present with income rows' do
    sign_in
    get simulator_path
    # non_retired household has CPP/OAS/pension benefits — should produce income rows
    assert_select 'details#income_breakdown table tbody tr'
  end

  test 'form has turbo frame target for live update' do
    sign_in
    get simulator_path
    assert_select "form[data-turbo-frame='simulation_results']"
  end

  test 'turbo frame wrapper is present around charts' do
    sign_in
    get simulator_path
    assert_select 'turbo-frame#simulation_results'
  end

  test 'reset link points to bare simulation path with full-page navigation' do
    sign_in
    get simulator_path
    assert_select "a[href='#{simulator_path}'][data-turbo-frame='_top']", text: 'Reset'
  end
end
