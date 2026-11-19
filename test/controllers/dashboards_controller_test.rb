require 'test_helper'

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:working_user_john)
  end

  def sign_in(user = @user)
    act_as(user)
  end

  test 'GET /dashboard returns 200' do
    sign_in
    get dashboard_path
    assert_response :success
  end

  # John retires 2045, Jane retires 2046 — the Income Projection should not
  # start until the whole household is retired, so the working member's missing
  # salary in 2045 is never shown as a misleading low-income year.
  test 'income projection starts at the year the whole household is retired' do
    sign_in
    get dashboard_path

    labels = JSON.parse(css_select('#income_projection').first['data-income-chart-labels-value'])
    assert_equal 2046, labels.first, 'Income Projection should begin the year both members are retired'
    assert_not_includes labels, 2045, 'The staggered year where one member still works should be excluded'
  end

  # Real-dollar income lands ±$1 off the goal from nominal→real rounding, which
  # the auto-scaled y-axis magnifies into visible wobble. Plotted values are
  # rounded to the nearest $1,000 to collapse that noise.
  test 'real-dollar income series are rounded to the nearest $1,000' do
    sign_in
    get dashboard_path

    data = JSON.parse(css_select('#income_projection').first['data-income-chart-real-income-data-value'])

    totals = data['total_income']
    assert totals.any?, 'expected real income data to be present'
    assert(totals.all? { |v| (v % 1000).zero? }, "total income should be multiples of 1000: #{totals.inspect}")

    goals = data['income_goal'].compact
    assert goals.any?, 'expected real income goal data to be present'
    assert(goals.all? { |v| (v % 1000).zero? }, "income goal should be multiples of 1000: #{goals.inspect}")
  end
end
