# Tallyloot is self-hosted: each install serves a single household and has no
# login. Every request acts as the household's first member, created with
# sample data on the first visit.
module SelfHosted
  module_function

  class MultipleHouseholdsError < StandardError; end

  # Refuses to pick an owner from a database with several households (e.g. one
  # restored from the old hosted service), which would hand one household's
  # data to every visitor.
  def owner
    household_count = Household.count
    if household_count > 1
      raise MultipleHouseholdsError,
            "Tallyloot serves one household per install, but this database has #{household_count}. " \
            'Start from a fresh database.'
    end

    User.where(household: Household.first).order(:id).first || SampleHousehold.create!.users.first
  end
end
