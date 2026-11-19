module Projection
  class Account
    attr_reader :account, :portfolio

    delegate :name, :balance, :user, to: :account

    def initialize(account, portfolio)
      @account = account
      @portfolio = portfolio
    end

    def periods(start_year = Time.zone.now.year, end_year = account.user.life_expectancy_year)
      opening_balance = account.balance || 0

      (start_year..end_year).map do |year|
        period = Period::Account.from_account(account, portfolio, year, opening_balance:)

        opening_balance = period.ending_balance
        period
      end
    end
  end
end
