# =============================================================================
# Fully set up test household: John and Jane Doe
# Tallyloot serves one household per install, so this is the only one seeded.
# =============================================================================

return if Rails.env.production?

household = Household.first_or_initialize
household.update!(retirement_income_goal: 150_000)

john_birthdate = Time.zone.parse('1980-01-01')

# Create John (primary user)
john = household.users.find_or_initialize_by(name: 'John')
john.update!(
  birth_date: john_birthdate,
  name: 'John',
  life_expectancy: 90,
  retirement_age: 65,
  household: household
)

# Create accounts for John
john.accounts.destroy_all
[
  { name: 'TFSA', balance: 123_000, contribution: 6_500, type: 'Account::Tfsa' },
  { name: 'RRSP', balance: 561_000, contribution: 19_000, type: 'Account::Rrsp', conversion_age: 71 },
  { name: 'Spousal RRSP', balance: 56_000, type: 'Account::Rrsp', conversion_age: 71 },
  { name: 'LIRA', balance: 499_000, type: 'Account::Lira', conversion_age: 65, provincial_jurisdiction: 'AB' },
].each { |attrs| john.accounts.create!(**attrs) }

# Create portfolio
default_glidepath = Glidepath.default
portfolio = household.portfolio || household.build_portfolio
portfolio.update!(
  inflation_rate: 0.03,
  glidepath: default_glidepath
)

# Create pension for John
john.pensions.destroy_all
john.pensions.create!(
  name: 'LAPP',
  description: 'Old work pension',
  annual_amount: 7_500,
  start_age: john.retirement_age
)

# Create benefits for John
john.benefits.destroy_all
[
  { name: 'CPP', annual_amount: 1500 * 12, start_age: 65, inflation_indexed: true, type: 'Benefit::Cpp' },
  { name: 'OAS', annual_amount: 8900, start_age: 65, inflation_indexed: true, type: 'Benefit::Oas' },
].each { |attrs| john.benefits.create!(**attrs) }

Rails.logger.info '  ✓ Created test user: John Doe'

# Create Jane (spouse)
jane = household.users.find_or_initialize_by(name: 'Jane')
jane.update!(
  birth_date: john_birthdate + 2.years,
  name: 'Jane',
  life_expectancy: 93,
  retirement_age: 60,
  household: household
)

# Create accounts for John
jane.accounts.destroy_all
[
  { name: 'TFSA', balance: 69_794, type: 'Account::Tfsa' },
  { name: 'RRSP', balance: 103_578, type: 'Account::Rrsp', conversion_age: 71 },
].each { |attrs| jane.accounts.create!(**attrs) }

Rails.logger.info '  ✓ Created spouse: Jane Doe'
