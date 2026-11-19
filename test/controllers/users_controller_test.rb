require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @single_user = users(:single_user)
    @household = households(:single)
  end

  def sign_in(user = @single_user)
    act_as(user)
  end

  test 'creates spouse and redirects to household settings' do
    sign_in
    assert_difference 'User.count', 1 do
      post users_path, params: {
        user: {
          name: 'Sam',
          birth_date: '1987-03-20',
          retirement_age: 63,
          life_expectancy: 85,
        },
      }
    end
    assert_redirected_to household_path
    assert_match 'Sam', flash[:notice]
  end

  test 'new spouse belongs to the current household' do
    sign_in
    post users_path, params: {
      user: {
        name: 'Sam',
        birth_date: '1987-03-20',
        retirement_age: 63,
        life_expectancy: 85,
      },
    }
    spouse = @household.users.find_by(name: 'Sam')
    assert_equal @household, spouse.household
  end

  test 'invalid spouse params re-renders household settings' do
    sign_in
    assert_no_difference 'User.count' do
      post users_path, params: {
        user: {
          name: '',
          birth_date: '',
        },
      }
    end
    assert_response :unprocessable_entity
  end
end
