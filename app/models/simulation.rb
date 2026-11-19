# Simulation builds a modified Projection::Household from URL parameters
# without persisting anything to the database.
#
# Parameters shape (all values are strings from params):
#   {
#     retirement_income_goal: "80000",
#     glidepath_id: "2",
#     users: { "1" => { retirement_age: "62", life_expectancy: "88" } },
#     accounts: { "5" => { contribution: "12000" } },
#     pensions: { "3" => { start_age: "60" } },
#     benefits: { "7" => { start_age: "65" } }
#   }
#
# IMPORTANT: ActiveRecord#dup clears the primary key (id) on the duplicated
# object. We must reassign the original id after each dup so that balance
# tracking (update_balances), Period::Account#account_id, and
# WithdrawalAllocation#withdrawal_for can all match objects by id correctly.
#
# We also set the :user association target on dup'd pensions and benefits so
# that start_year / income_eligible? resolve through the in-memory sim user
# rather than firing an extra DB query for the original AR user.
#
class Simulation
  SimHousehold = Struct.new(:retirement_income_goal, :users) do
    def retired_as_of?(year) = users.any? { |u| u.retired_as_of?(year) }
    def fully_retired_as_of?(year) = users.any? && users.all? { |u| u.retired_as_of?(year) }
    def eldest_user = users.min_by(&:birth_date)
    def terminal_year = users.map(&:life_expectancy_year).max
    def user_ages_in_year(year) = users.map { |u| u.age_in_year(year) }.join(', ')
  end

  def initialize(household, params)
    @household = household
    @params = params.to_h.with_indifferent_access
  end

  def projection
    Projection::Household.new(
      household: sim_household,
      portfolio: sim_portfolio,
      users: sim_users,
      accounts: sim_accounts,
      pensions: sim_pensions,
      benefits: sim_benefits,
      employments: sim_employments
    )
  end

  private

  def sim_household
    income_goal = @params[:retirement_income_goal].presence&.to_i || @household.retirement_income_goal
    SimHousehold.new(income_goal, sim_users)
  end

  def sim_portfolio
    portfolio = @household.portfolio.dup
    portfolio.id = @household.portfolio.id
    portfolio.glidepath_id = @params[:glidepath_id].to_i if @params[:glidepath_id].present?
    portfolio
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
  def sim_users
    @sim_users ||= @household.users.map do |u|
      p = (@params.dig(:users, u.id.to_s) || {}).with_indifferent_access
      u.dup.tap do |d|
        d.id = u.id
        d.retirement_age = p[:retirement_age].presence&.to_i || u.retirement_age
        d.life_expectancy = p[:life_expectancy].presence&.to_i || u.life_expectancy
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

  def sim_accounts
    @household.accounts.map do |account|
      p = (@params.dig(:accounts, account.id.to_s) || {}).with_indifferent_access
      account.dup.tap do |d|
        d.id = account.id
        d.contribution = p[:contribution].presence&.to_i || account.contribution
      end
    end
  end

  # rubocop:disable Metrics/AbcSize
  def sim_pensions
    sim_users_by_id = sim_users.index_by(&:id)
    @household.pensions.map do |pension|
      p = (@params.dig(:pensions, pension.id.to_s) || {}).with_indifferent_access
      pension.dup.tap do |d|
        d.id = pension.id
        d.start_age = p[:start_age].presence&.to_i || pension.start_age
        # Point the association to the in-memory sim user so start_year and
        # income_eligible? resolve without a DB hit.
        d.association(:user).target = sim_users_by_id[pension.user_id]
      end
    end
  end

  def sim_benefits
    sim_users_by_id = sim_users.index_by(&:id)
    @household.benefits.map do |benefit|
      p = (@params.dig(:benefits, benefit.id.to_s) || {}).with_indifferent_access
      benefit.dup.tap do |d|
        d.id = benefit.id
        d.start_age = p[:start_age].presence&.to_i || benefit.start_age
        # Point the association to the in-memory sim user so start_year and
        # income_eligible? resolve without a DB hit.
        d.association(:user).target = sim_users_by_id[benefit.user_id]
      end
    end
  end

  def sim_employments
    sim_users_by_id = sim_users.index_by(&:id)
    @household.employments.map do |employment|
      p = (@params.dig(:employments, employment.id.to_s) || {}).with_indifferent_access
      employment.dup.tap do |d|
        d.id = employment.id
        d.annual_income = p[:annual_income].presence&.to_i || employment.annual_income
        d.end_age = p[:end_age].presence&.to_i || employment.end_age
        d.association(:user).target = sim_users_by_id[employment.user_id]
      end
    end
  end
  # rubocop:enable Metrics/AbcSize
end
