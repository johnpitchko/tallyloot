# Period::Employment represents an employment record's earned income for a single year.
#
# Post-retirement employment income (consulting, part-time work, etc.) is
# calculated by asking the Employment model whether the user falls within the
# configured start_age/end_age window for that year.
#
# Created by Projection::Household and included in Period::Summary for income
# totals and OAS clawback calculations (see TODO in Period::Summary).
module Period
  class Employment
    include Inspectable

    inspectable :year, :employment_id, :name, :income_amount
    attr_reader :year, :employment_id, :name, :income_amount

    def self.from_employment(employment, year)
      new(
        year,
        employment_id: employment.id,
        name: employment.label,
        income_amount: employment.income_in_year(year)
      )
    end

    def initialize(year, employment_id: nil, name: nil, income_amount: 0)
      @year = year
      @employment_id = employment_id
      @name = name
      @income_amount = income_amount
    end
  end
end
