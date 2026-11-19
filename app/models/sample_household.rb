# Builds the example household a self-hosted install starts with, so the
# dashboard shows a real projection before the person has entered anything.
class SampleHousehold
  AGE = 40

  def self.create!
    new.create!
  end

  # rubocop:disable Metrics/MethodLength
  def create!
    Household.transaction do
      household = Household.create!(
        province: 'ON',
        retirement_income_goal: 60_000,
        sample_data: true
      )
      Portfolio.create!(household:, inflation_rate: 0.025, glidepath: default_glidepath)
      user = household.users.create!(
        name: 'Alex',
        birth_date: Date.new(Time.zone.today.year - AGE, 1, 1),
        retirement_age: 65,
        life_expectancy: 90
      )
      add_finances(user)
      household
    end
  end
  # rubocop:enable Metrics/MethodLength

  private

  def add_finances(user)
    user.accounts.create!(name: 'RRSP', type: 'Account::Rrsp', balance: 120_000, contribution: 10_000,
                          conversion_age: 71)
    user.accounts.create!(name: 'TFSA', type: 'Account::Tfsa', balance: 60_000, contribution: 7_000)
    user.benefits.create!(name: 'CPP', type: 'Benefit::Cpp', annual_amount: 12_000, start_age: 65,
                          inflation_indexed: true)
    user.benefits.create!(name: 'OAS', type: 'Benefit::Oas', annual_amount: 8_900, start_age: 65,
                          inflation_indexed: true)
  end

  def default_glidepath
    Glidepath.find_by(name: Glidepath::DEFAULT_GLIDEPATH_NAME) || Glidepath.first
  end
end
