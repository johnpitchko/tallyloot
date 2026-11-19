# Period::Benefit represents a government benefit's income for a single year.
#
# Benefits are government income sources (CPP, OAS, etc.) that pay an annual
# amount starting when the user reaches a specified age.
#
# The income_amount is calculated by the Benefit model's annual_amount_nominal method,
# which returns $0 if the user hasn't reached the start_age, and handles inflation
# indexing for eligible benefits.
#
# Created by Projection::Household and included in Period::Summary for income totals.
#
module Period
  class Benefit
    include Inspectable

    inspectable :year, :benefit_id, :name, :income_amount
    attr_reader :year, :benefit_id, :name, :income_amount

    def self.from_benefit(benefit, _portfolio, year)
      new(
        year,
        benefit_id: benefit.id,
        name: benefit.name,
        income_amount: benefit.annual_amount_nominal(year)
      )
    end

    def initialize(year, benefit_id: nil, name: nil, income_amount: 0)
      @year = year
      @benefit_id = benefit_id
      @name = name
      @income_amount = income_amount
    end
  end
end
