# Period::WithdrawalAllocation determines how much to withdraw from each account
# to meet a household's retirement income goal for a single year.
#
# Allocation strategy:
# 1. First, satisfy mandatory minimums (RRIF/LIF requirements)
# 2. Then, allocate remaining need by withdrawal priority:
#    - Priority 1: Non-registered accounts (withdraw first, most tax-efficient)
#    - Priority 2: Registered accounts (RRSP/RRIF)
#    - Priority 3: TFSA (withdraw last, preserve tax-free growth)
# 3. Within a priority group, withdraw proportionally by balance
#
# The allocation respects account constraints:
# - Minimum withdrawals (RRIF/LIF mandatory minimums based on age)
# - Maximum withdrawals (LIF caps based on age and province)
#
# Handles account conversions (RRSP→RRIF, LIRA→LIF) by checking the effective
# account type for the year. A converted RRSP uses RRIF minimum withdrawal rates.
#
# Used by Projection::Household when household is retired.
# The withdrawal_for(account) method provides the allocated amount for each account,
# which is then passed to Period::Account as allocated_withdrawal.
#
module Period
  class WithdrawalAllocation
    include Inspectable

    attr_reader :year, :income_goal, :guaranteed_income, :account_balances, :user_ages

    inspectable :year, :income_goal, :guaranteed_income, :withdrawal_need, :total_withdrawals, :shortfall

    def initialize(year:, income_goal:, guaranteed_income:, account_balances:, user_ages: {})
      @year = year
      @income_goal = income_goal || 0
      @guaranteed_income = guaranteed_income || 0
      @account_balances = account_balances
      @user_ages = user_ages
      @allocations = nil
    end

    def withdrawal_need = [income_goal - guaranteed_income, 0].max
    def total_withdrawals = allocations.sum { |a| a[:withdrawal] }
    def shortfall = [withdrawal_need - total_withdrawals, 0].max
    def allocations = @allocations ||= compute_allocations

    def withdrawal_for(account)
      allocation = allocations.find { |a| a[:account].id == account.id }
      allocation ? allocation[:withdrawal] : 0
    end

    private

    def compute_allocations
      result = initialize_allocations
      remaining = allocate_mandatory_minimums(result, withdrawal_need)
      allocate_by_priority(result, remaining)
      result
    end

    def initialize_allocations
      account_balances.map do |ab|
        {
          account: ab[:account],
          balance: ab[:balance],
          withdrawal: 0,
          mandatory_minimum: mandatory_minimum_for(ab[:account], ab[:balance]),
        }
      end
    end

    def allocate_mandatory_minimums(allocations, remaining_need)
      allocations.each do |alloc|
        minimum = alloc[:mandatory_minimum]
        next if minimum.zero?

        alloc[:withdrawal] = minimum
        remaining_need -= minimum
      end

      remaining_need
    end

    def allocate_by_priority(allocations, remaining_need)
      return remaining_need if remaining_need <= 0

      # Group accounts by withdrawal priority
      priority_groups = allocations.group_by { |a| a[:account].withdrawal_priority }

      priority_groups.keys.sort.each do |priority|
        break if remaining_need <= 0

        group = priority_groups[priority]
        remaining_need = allocate_within_priority(group, remaining_need)
      end

      remaining_need
    end

    def allocate_within_priority(group, remaining_need)
      return remaining_need if remaining_need <= 0

      available_in_group = group.sum { |a| available_for_withdrawal(a) }
      return remaining_need if available_in_group <= 0

      return withdraw_all_from_group(group, remaining_need, available_in_group) if remaining_need >= available_in_group

      allocate_proportionally(group, remaining_need)
      0
    end

    def withdraw_all_from_group(group, remaining_need, available_in_group)
      group.each { |alloc| alloc[:withdrawal] += available_for_withdrawal(alloc) }
      remaining_need - available_in_group
    end

    def allocate_proportionally(group, amount_to_allocate)
      total_available = group.sum { |a| available_for_withdrawal(a) }
      return if total_available <= 0

      group.each do |alloc|
        available = available_for_withdrawal(alloc)
        proportion = available.to_f / total_available
        alloc[:withdrawal] += (amount_to_allocate * proportion).round
      end
    end

    def available_for_withdrawal(alloc)
      max_withdrawal = max_withdrawal_for(alloc[:account], alloc[:balance])
      [max_withdrawal - alloc[:withdrawal], 0].max
    end

    def max_withdrawal_for(account, balance)
      return balance unless account.maximum_withdrawal?(year)

      age = user_ages[account.user_id]
      rate = account.maximum_withdrawal_rate(age)
      rate ? (balance * rate).round : balance
    end

    def mandatory_minimum_for(account, balance)
      return 0 unless account.minimum_withdrawal?(year) && account.can_withdraw?(year)

      age = user_ages[account.user_id]
      return 0 unless age

      (balance * account.minimum_withdrawal_rate(age)).round
    end
  end
end
