# Period::Pension represents a pension's income for a single year.
#
# Pensions are defined benefit income sources (e.g., employer pensions, LAPP)
# that pay a fixed annual amount starting at a specified year.
#
# The income_amount is calculated by the Pension model's annual_amount_nominal method,
# which handles inflation indexing if applicable.
#
# Created by Projection::Household and included in Period::Summary for income totals.
#
module Period
  class Pension
    include Inspectable

    inspectable :year, :pension_id, :name, :income_amount
    attr_reader :year, :pension_id, :name, :income_amount

    def self.from_pension(pension, _portfolio, year)
      new(
        year,
        pension_id: pension.id,
        name: pension.name,
        income_amount: pension.annual_amount_nominal(year)
      )
    end

    def initialize(year, pension_id: nil, name: nil, income_amount: 0)
      @year = year
      @pension_id = pension_id
      @name = name
      @income_amount = income_amount
    end
  end
end
