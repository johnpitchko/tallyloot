require 'test_helper'

class HouseholdsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:working_user_john)
    @single_user = users(:single_user)
  end

  def sign_in(user = @user)
    act_as(user)
  end

  test 'shows add-spouse section when household has no spouse' do
    sign_in @single_user
    get household_path
    assert_response :success
    assert_select '#add_spouse'
  end

  test 'hides add-spouse section when spouse already exists' do
    sign_in
    get household_path
    assert_response :success
    assert_select '#add_spouse', count: 0
  end
end
