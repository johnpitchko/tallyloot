# WhatIf builds a focused "what-if" scenario covering the decisions that most
# affect a Canadian retirement plan. Unlike Simulate (which exposes every field),
# WhatIf is intentionally limited to lifestyle questions:
#
#   users       — hash of { user_id => { retirement_age: integer, monthly_savings_delta: integer,
#                                         pension_start_age: integer } }
#   benefits    — hash of { benefit_id => { start_age: integer } } CPP/OAS timing only
#   employments — hash of { employment_id => { annual_income: integer, end_age: integer } }
#
# pension_start_age is a single age applied to ALL of a user's DB pensions (fan-out happens here).
# Glidepath belongs on the Simulate page.
#
# #adjustments returns an array of WhatIf::Adjustment::* objects — one per changed lever.
# Each adjustment responds to #text and #type for display in the What If? insights box.
#
# rubocop:disable Metrics/ClassLength
class WhatIf
  def initialize(household, params)
    @household = household
    @params    = params.to_h.with_indifferent_access
  end

  def projection
    Simulation.new(@household, sim_params).projection
  end

  def adjustments
    [
      *retirement_age_adjustments,
      *monthly_savings_adjustments,
      *benefit_timing_adjustments,
      *pension_timing_adjustments,
      *employment_adjustments,
    ].compact.select(&:changed?)
  end

  def warnings
    benefit_warnings + pension_warnings
  end

  private

  # ─── Adjustment factories ────────────────────────────────────────────────────

  def retirement_age_adjustments
    user_param_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.filter_map do |user|
      new_age = user_param_overrides.dig(user.id.to_s, :retirement_age).presence&.to_i
      next unless new_age

      WhatIf::Adjustment::RetirementAge.new(user, new_age)
    end
  end

  def monthly_savings_adjustments
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.map do |user|
      delta = user_overrides.dig(user.id.to_s, :monthly_savings_delta).to_i
      WhatIf::Adjustment::MonthlySavings.new(user, delta)
    end
  end

  def benefit_timing_adjustments
    benefit_overrides = (@params[:benefits] || {}).with_indifferent_access
    @household.benefits.filter_map do |benefit|
      new_age = benefit_overrides.dig(benefit.id.to_s, :start_age).presence&.to_i
      next unless new_age

      adj = WhatIf::Adjustment::BenefitTiming.new(benefit, new_age, inflation_rate: inflation_rate)
      adj if adj.changed? && adj.breakeven
    end
  end

  def pension_timing_adjustments
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.flat_map do |user|
      new_age = user_overrides.dig(user.id.to_s, :pension_start_age).presence&.to_i
      next [] unless new_age

      user.pensions.map do |pension|
        WhatIf::Adjustment::PensionTiming.new(pension, new_age, inflation_rate: inflation_rate)
      end
    end
  end

  def employment_adjustments
    employment_overrides = (@params[:employments] || {}).with_indifferent_access
    @household.employments.filter_map do |employment|
      new_end_age = employment_overrides.dig(employment.id.to_s, :end_age).presence&.to_i
      next unless new_end_age

      WhatIf::Adjustment::Employment.new(employment, new_end_age: new_end_age)
    end
  end

  # ─── Simulation params ───────────────────────────────────────────────────────

  # rubocop:disable Metrics/AbcSize
  def sim_params
    {}.tap do |p|
      p[:users]       = users_params if user_retirement_ages_changed?
      p[:accounts]    = accounts_params if monthly_savings_changed?
      p[:benefits]    = benefits_params if benefits_start_ages_changed?
      p[:pensions]    = pensions_params if pension_start_ages_changed?
      p[:employments] = employments_params if employments_changed?
    end
  end

  # rubocop:enable Metrics/AbcSize

  def user_retirement_ages_changed?
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.any? do |user|
      override_age = user_overrides.dig(user.id.to_s, :retirement_age).presence&.to_i
      override_age && override_age != user.retirement_age
    end
  end

  def users_params
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.each_with_object({}) do |user, h|
      age = user_overrides.dig(user.id.to_s, :retirement_age).presence&.to_i || user.retirement_age
      h[user.id.to_s] = { retirement_age: age }
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
  def accounts_params
    user_overrides = (@params[:users] || {}).with_indifferent_access
    result = {}
    @household.users.each do |user|
      delta = user_overrides.dig(user.id.to_s, :monthly_savings_delta).to_i
      next if delta.zero?

      annual_delta    = delta * 12
      target_accounts = user.accounts.select { |a| a.contribution.to_i.positive? }
      target_accounts = user.accounts if target_accounts.empty?
      next if target_accounts.empty?

      per_account = (annual_delta.to_f / target_accounts.size).round
      target_accounts.each do |account|
        result[account.id.to_s] = { contribution: [account.contribution.to_i + per_account, 0].max }
      end
    end
    result
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity

  def benefits_params
    benefit_overrides = (@params[:benefits] || {}).with_indifferent_access
    @household.benefits.each_with_object({}) do |benefit, h|
      new_age = benefit_overrides.dig(benefit.id.to_s, :start_age).presence&.to_i
      h[benefit.id.to_s] = { start_age: new_age } if new_age
    end
  end

  def pensions_params
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.each_with_object({}) do |user, h|
      new_age = user_overrides.dig(user.id.to_s, :pension_start_age).presence&.to_i
      next unless new_age

      user.pensions.each { |pension| h[pension.id.to_s] = { start_age: new_age } }
    end
  end

  def employments_params
    employment_overrides = (@params[:employments] || {}).with_indifferent_access
    @household.employments.each_with_object({}) do |employment, h|
      new_end_age = employment_overrides.dig(employment.id.to_s, :end_age).presence&.to_i
      h[employment.id.to_s] = { end_age: new_end_age } if new_end_age
    end
  end

  # ─── Helpers ─────────────────────────────────────────────────────────────────

  def monthly_savings_changed?
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.any? do |user|
      user_overrides.dig(user.id.to_s, :monthly_savings_delta).to_i != 0
    end
  end

  def benefits_start_ages_changed?
    benefit_overrides = (@params[:benefits] || {}).with_indifferent_access
    @household.benefits.any? do |benefit|
      new_age = benefit_overrides.dig(benefit.id.to_s, :start_age).presence&.to_i
      new_age && new_age != benefit.start_age
    end
  end

  def pension_start_ages_changed?
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.any? do |user|
      new_age = user_overrides.dig(user.id.to_s, :pension_start_age).presence&.to_i
      new_age && user.pensions.any? { |p| new_age != p.start_age }
    end
  end

  def employments_changed?
    employment_overrides = (@params[:employments] || {}).with_indifferent_access
    @household.employments.any? do |employment|
      new_end_age = employment_overrides.dig(employment.id.to_s, :end_age).presence&.to_i
      new_end_age && new_end_age != employment.end_age
    end
  end

  def inflation_rate
    @household.portfolio.inflation_rate
  end

  def effective_retirement_age(user)
    (@params[:users] || {}).with_indifferent_access.dig(user.id.to_s, :retirement_age).presence&.to_i ||
      user.retirement_age
  end

  def benefit_warnings
    benefit_overrides = (@params[:benefits] || {}).with_indifferent_access
    @household.benefits.filter_map do |benefit|
      selected_age = benefit_overrides.dig(benefit.id.to_s, :start_age).presence&.to_i
      next unless selected_age

      ret_age = effective_retirement_age(benefit.user)
      next unless selected_age < ret_age

      "#{benefit.user.name}: #{benefit.name} start age (#{selected_age}) is before " \
        "retirement age (#{ret_age})."
    end
  end

  def pension_warnings
    user_overrides = (@params[:users] || {}).with_indifferent_access
    @household.users.filter_map do |user|
      pension_age = user_overrides.dig(user.id.to_s, :pension_start_age).presence&.to_i
      next unless pension_age

      ret_age = effective_retirement_age(user)
      next unless pension_age < ret_age

      "#{user.name}: Pension start age (#{pension_age}) is before retirement age (#{ret_age})."
    end
  end
end
# rubocop:enable Metrics/ClassLength
