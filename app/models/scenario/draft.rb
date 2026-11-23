class Scenario
  # An in-memory working copy of a household's records.
  #
  # These records are deliberately NEVER SAVED. Levers mutate them and
  # Projection::Household reads them. Nothing in this path calls save, update,
  # or destroy.
  #
  # Loaded via Household.includes(users: ...).find rather than from the caller's
  # household object, for two reasons:
  #
  #   1. Isolation. Household-scope levers mutate household.retirement_income_goal
  #      and portfolio.glidepath_id. Using the caller's objects would leak those
  #      mutations back into the request that asked for the projection.
  #
  #   2. Correctness. Household#terminal_year and #retired_as_of? read
  #      household.users. Eager-loading through the household makes that
  #      association the same objects the levers mutate, so both follow the draft
  #      rather than the database.
  #
  # inverse_of wires account.user / pension.user to the in-memory user, so no
  # association repair is needed and no record is duplicated. Do not reintroduce
  # ActiveRecord#dup here: it clears the primary key, and the engine matches
  # records by id (app/models/projection/household.rb:69).
  class Draft
    attr_reader :household

    def self.from(household)
      new(Household.includes(users: %i[accounts pensions benefits employment]).find(household.id))
    end

    def initialize(household)
      @household = household
    end

    def users = household.users.to_a
    delegate :portfolio, to: :household
    def accounts = users.flat_map(&:accounts)
    def pensions = users.flat_map(&:pensions)
    def benefits = users.flat_map(&:benefits)
    def employments = users.filter_map(&:employment)

    def user(id) = users.find { |u| u.id == id }

    def to_projection
      Projection::Household.new(
        household: household,
        portfolio: portfolio,
        users: users,
        accounts: accounts,
        pensions: pensions,
        benefits: benefits,
        employments: employments
      )
    end
  end
end
