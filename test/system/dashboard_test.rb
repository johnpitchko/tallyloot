require 'application_system_test_case'

class DashboardTest < ApplicationSystemTestCase
  test 'editing an account in the input panel updates the dashboard' do
    account = accounts(:tfsa_john)
    act_as users(:working_user_john)

    visit root_path
    click_link "edit_account_link_#{account.id}"

    within "#edit_account_#{account.id}" do
      # Focus first: the currency input rewrites its value on focus.
      balance = find_field('account_balance')
      balance.click
      balance.set('150000')
      click_button 'Update Account'
    end

    within "#account_#{account.id}" do
      assert_text '$150,000'
    end
  end
end
