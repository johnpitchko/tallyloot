module Projection
  class Pension
    attr_reader :pension, :portfolio

    def initialize(pension, portfolio)
      @pension = pension
      @portfolio = portfolio
    end

    def periods(start_year, end_year)
      (start_year...end_year).map do |year|
        Period::Pension.from_pension(pension, portfolio, year)
      end
    end
  end
end
