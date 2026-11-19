require 'test_helper'

class SelfHostedTest < ActionDispatch::IntegrationTest
  setup do
    # Self-hosted installs hold a single household; clear the other fixtures.
    ActiveRecord::Base.connection.disable_referential_integrity do
      Household.where.not(id: households(:non_retired).id).delete_all
    end
    @owner = SelfHosted.owner
    @household = @owner.household
  end

  test 'visitors land on the dashboard without logging in' do
    get root_path

    assert_response :success
    assert_select '#workspace_inputs'
    assert_select '#workspace_results'
  end

  test 'a fresh install starts with a sample household' do
    ActiveRecord::Base.connection.disable_referential_integrity { Household.delete_all }

    assert_difference 'Household.count', 1 do
      get root_path
    end
    assert_response :success
    assert_select '#sample_data_notice'
  end

  test 'saving from a dashboard frame refreshes the page' do
    get root_path

    post user_accounts_path(@owner),
         params: { account: { name: 'New TFSA', type: 'Account::Tfsa', balance: 5000 } },
         headers: { 'Turbo-Frame' => 'account_form' }, as: :turbo_stream

    assert_response :success
    assert_match '<turbo-stream action="refresh"', response.body
    assert @owner.accounts.exists?(name: 'New TFSA')
  end

  test 'an account can move to another person in the household' do
    account = accounts(:tfsa_john)
    partner = users(:working_user_jane)

    patch user_account_path(account.user, account), params: { account: { user_id: partner.id } }

    assert_equal partner, account.reload.user
  end

  test 'an account cannot move to someone outside the household' do
    account = accounts(:tfsa_john)

    patch user_account_path(account.user, account), params: { account: { user_id: users(:retired_user_bob).id } }

    assert_response :not_found
    assert_equal users(:working_user_john), account.reload.user
  end

  test 'adding a partner from the dashboard refreshes the page' do
    get root_path

    assert_difference -> { @household.users.count }, 1 do
      post users_path,
           params: { user: { name: 'Sam', birth_date: '1985-04-01', retirement_age: 63, life_expectancy: 90 } },
           headers: { 'Turbo-Frame' => 'person_form' }, as: :turbo_stream
    end
    assert_match '<turbo-stream action="refresh"', response.body
  end

  test 'refuses to serve a database holding several households' do
    Household.create!

    assert_raises(SelfHosted::MultipleHouseholdsError) { get root_path }
  end

  test 'sample-data notice shows until dismissed' do
    @household.update!(sample_data: true)

    get root_path
    assert_select '#sample_data_notice'

    delete sample_notice_path
    assert_redirected_to root_path
    assert_not @household.reload.sample_data?
  end
end
