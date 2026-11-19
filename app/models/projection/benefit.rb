module Projection
  class Benefit
    attr_reader :benefit, :portfolio

    def initialize(benefit, portfolio)
      @benefit = benefit
      @portfolio = portfolio
    end

    def periods(start_year, end_year)
      (start_year...end_year).map do |year|
        Period::Benefit.from_benefit(benefit, portfolio, year)
      end
    end
  end
end
