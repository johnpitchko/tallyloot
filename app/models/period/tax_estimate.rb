module Period
  # Represents an estimated income tax liability for a single year.
  # Computed from taxable income (pensions + benefits + taxable account withdrawals).
  # TFSA withdrawals are excluded as they are not taxable.
  #
  # Structured to hold federal and provincial components separately so that
  # provincial tax can be added in a future phase without changing the interface.
  class TaxEstimate
    include Inspectable

    inspectable :taxable_income, :federal_tax, :estimated_tax, :effective_rate

    attr_reader :taxable_income, :federal_tax, :provincial_tax

    def initialize(taxable_income:, federal_tax:, provincial_tax: 0)
      @taxable_income = taxable_income
      @federal_tax = federal_tax
      @provincial_tax = provincial_tax
    end

    def estimated_tax
      federal_tax + provincial_tax
    end

    def effective_rate
      return 0.0 if taxable_income <= 0

      (estimated_tax.to_f / taxable_income).round(4)
    end
  end
end
