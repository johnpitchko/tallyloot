require 'test_helper'

module Period
  class WithdrawalAllocationTest < ActiveSupport::TestCase
    setup do
      @user = users(:working_user_john)
      @tfsa = accounts(:tfsa_john)
      @rrif = ::Account::Rrsp.new(user: @user, name: 'Test RRSP/RRIF', balance: 100_000, conversion_age: 55)
      @non_registered = ::Account::NonRegistered.new(user: @user, name: 'Non-Reg', balance: 50_000)
    end

    test 'withdrawal_need returns zero when guaranteed income meets goal' do
      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: 50_000,
        guaranteed_income: 60_000,
        account_balances: []
      )

      assert_equal 0, allocation.withdrawal_need
    end

    test 'withdrawal_need returns difference when goal exceeds guaranteed' do
      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: 80_000,
        guaranteed_income: 30_000,
        account_balances: []
      )

      assert_equal 50_000, allocation.withdrawal_need
    end

    test 'allocates from non-registered before TFSA' do
      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: 60_000,
        guaranteed_income: 30_000,
        account_balances: [
          { account: @tfsa, balance: 100_000 },
          { account: @non_registered, balance: 100_000 },
        ],
        user_ages: { @user.id => 65 }
      )

      # Need 30,000 withdrawal
      # Non-registered has priority 1, TFSA has priority 3
      # Should take all from non-registered first
      assert_equal 30_000, allocation.withdrawal_for(@non_registered)
      assert_equal 0, allocation.withdrawal_for(@tfsa)
    end

    test 'allocates proportionally within same priority tier' do
      # Use saved accounts so they have IDs
      rrsp1 = accounts(:rrsp_john) # balance 200_000
      rrsp2 = accounts(:rrsp_jane) # balance 100_000

      # Mock the accounts to allow withdrawal
      rrsp1.define_singleton_method(:can_withdraw?) { |_| true }
      rrsp2.define_singleton_method(:can_withdraw?) { |_| true }

      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: 60_000,
        guaranteed_income: 50_000,
        account_balances: [
          { account: rrsp1, balance: 60_000 },
          { account: rrsp2, balance: 40_000 },
        ],
        user_ages: { rrsp1.user_id => 70, rrsp2.user_id => 70 }
      )

      # Need 10,000 withdrawal
      # Both are priority 2, so allocate proportionally (60/40 split)
      assert_equal 6_000, allocation.withdrawal_for(rrsp1)
      assert_equal 4_000, allocation.withdrawal_for(rrsp2)
    end

    test 'shortfall calculated when accounts cannot meet need' do
      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: 100_000,
        guaranteed_income: 20_000,
        account_balances: [
          { account: @tfsa, balance: 30_000 },
        ],
        user_ages: { @user.id => 65 }
      )

      # Need 80,000 but only 30,000 available
      assert_equal 30_000, allocation.total_withdrawals
      assert_equal 50_000, allocation.shortfall
    end

    test 'mandatory minimums are allocated even when no withdrawal need' do
      # Use RRIF from retired user Sue who can actually withdraw
      rrif = accounts(:rrif_sue)

      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: 50_000,
        guaranteed_income: 60_000,
        account_balances: [
          { account: rrif, balance: 100_000 },
        ],
        user_ages: { rrif.user_id => 71 }
      )

      # At age 71, minimum rate is 5.28%
      expected_minimum = (100_000 * 0.0528).round
      assert_equal expected_minimum, allocation.withdrawal_for(rrif)
    end

    test 'handles nil income_goal gracefully' do
      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: nil,
        guaranteed_income: 30_000,
        account_balances: []
      )

      assert_equal 0, allocation.withdrawal_need
    end

    test 'handles nil guaranteed_income gracefully' do
      allocation = Period::WithdrawalAllocation.new(
        year: 2030,
        income_goal: 50_000,
        guaranteed_income: nil,
        account_balances: []
      )

      assert_equal 50_000, allocation.withdrawal_need
    end

    test 'priority order is non-registered then registered then TFSA' do
      # Priority 1: non-registered
      # Priority 2: registered (RRSP, RRIF, etc.)
      # Priority 3: TFSA
      assert_equal 1, @non_registered.withdrawal_priority
      assert_equal 2, @rrif.withdrawal_priority
      assert_equal 3, @tfsa.withdrawal_priority
    end
  end
end
