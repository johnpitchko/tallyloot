# Period::Account represents a single account's financial state for one year.
#
# It calculates the year's cash flow sequence:
#   Opening Balance → +Contribution → -Withdrawal → +Growth → Ending Balance
#
# Key behaviors:
# - Pre-retirement: Contributions are added, no withdrawals
# - Post-retirement: Withdrawals are taken via goal-based allocation
#   (allocated_withdrawal from Period::WithdrawalAllocation)
# - Respects account-specific rules (RRIF minimums, LIF maximums, etc.)
#
# Created by Projection::Household via the from_account factory method.
# The ending_balance becomes next year's opening_balance.
#
module Period
  class Account
    include Inspectable

    inspectable :year, :opening_balance, :contribution_amount, :nominal_return

    attr_reader :year, :account_id, :account, :opening_balance, :nominal_return, :retired,
                :user_age, :allocated_withdrawal

    # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
    def self.from_account(account, portfolio, year, user: nil, opening_balance: 0, allocated_withdrawal: nil)
      resolved_user = user || account.user
      user_age = resolved_user.age_in_year(year)
      nominal_return = portfolio.nominal_return_for_age(user_age)
      retired = resolved_user.retired_as_of?(year)

      new(
        year,
        account: account,
        opening_balance: opening_balance,
        contribution_amount: account.contribution,
        nominal_return: nominal_return,
        retired: retired,
        user_age: user_age,
        allocated_withdrawal: allocated_withdrawal
      )
    end
    # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

    # rubocop:disable Metrics/ParameterLists
    def initialize(year, account: nil, opening_balance: 0, contribution_amount: 0, nominal_return: 0,
                   retired: false, user_age: nil, allocated_withdrawal: nil)
      # rubocop:enable Metrics/ParameterLists
      @year = year
      @account = account
      @account_id = account&.id
      @opening_balance = opening_balance
      @contribution_amount = contribution_amount
      @nominal_return = nominal_return
      @retired = retired
      @user_age = user_age
      @allocated_withdrawal = allocated_withdrawal
    end

    def contribution_amount
      return 0 if retired
      return 0 if account&.converted_as_of?(year)

      @contribution_amount
    end

    def withdrawal_amount
      return 0 unless retired

      allocated_withdrawal || 0
    end

    def pre_growth_balance
      (opening_balance + contribution_amount - withdrawal_amount).round
    end

    def growth
      (pre_growth_balance * nominal_return).round
    end

    def ending_balance
      (pre_growth_balance + growth).round
    end
  end
end
