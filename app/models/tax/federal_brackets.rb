module Tax
  # Calculates Canadian federal income tax using 2024 bracket rates.
  # Bracket thresholds and the basic personal amount are inflated forward
  # from 2024 using the portfolio inflation rate to approximate future-year brackets.
  class FederalBrackets
    BASE_YEAR = 2024
    BASE_BASIC_PERSONAL_AMOUNT = 15_705
    QC_ABATEMENT_RATE = 0.165

    # 2024 federal marginal brackets: { lower threshold, marginal rate }
    BASE_BRACKETS = [
      { threshold: 0,       rate: 0.15 },
      { threshold: 55_867,  rate: 0.205 },
      { threshold: 111_733, rate: 0.26 },
      { threshold: 154_906, rate: 0.29 },
      { threshold: 220_000, rate: 0.33 },
    ].freeze

    def initialize(year:, inflation_rate: 0.02, province: nil)
      @year = year
      @inflation_rate = inflation_rate
      @province = province
    end

    def tax_on(gross_income)
      return 0 if gross_income <= 0

      net_income = [gross_income - basic_personal_amount, 0].max
      return 0 if net_income <= 0

      tax = calculate_marginal_tax(net_income)
      @province == 'QC' ? (tax * (1 - QC_ABATEMENT_RATE)).round : tax
    end

    def basic_personal_amount
      (BASE_BASIC_PERSONAL_AMOUNT * inflation_factor).round
    end

    def brackets
      BASE_BRACKETS.map { |b| { threshold: (b[:threshold] * inflation_factor).round, rate: b[:rate] } }
    end

    private

    def inflation_factor
      years_elapsed = [@year - BASE_YEAR, 0].max
      (1 + @inflation_rate)**years_elapsed
    end

    def calculate_marginal_tax(net_income)
      tax = 0.0
      bracket_list = brackets

      bracket_list.each_with_index do |bracket, i|
        lower = bracket[:threshold]
        next if net_income <= lower

        upper = bracket_list[i + 1]&.fetch(:threshold) || Float::INFINITY
        income_in_bracket = [net_income, upper].min - lower
        tax += income_in_bracket * bracket[:rate]
      end

      tax.round
    end
  end
end
