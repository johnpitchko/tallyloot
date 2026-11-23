# == Schema Information
#
# Table name: households
#
#  id                     :integer          not null, primary key
#  province               :string
#  retirement_income_goal :integer
#  sample_data            :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
class Household < ApplicationRecord
  include Inspectable

  PROVINCES = %w[AB BC MB NB NL NS NT NU ON PE QC SK YT].freeze

  has_many :users, dependent: :destroy
  has_many :accounts, through: :users
  has_many :pensions, through: :users
  has_many :benefits, through: :users
  has_many :employments, through: :users, source: :employment
  has_one :portfolio, dependent: :destroy
  has_many :scenarios, dependent: :destroy

  validates :province, inclusion: { in: PROVINCES }, allow_nil: true

  inspectable :province, :retirement_income_goal

  DEFAULT_MILESTONE_AGES = [55, 60, 65, 70, 75, 80, 85].freeze

  def max_life_expectancy_year
    return nil if users.empty?

    users.map(&:life_expectancy_year).max
  end

  def retired_as_of?(year)
    users.any? { |user| user.retired_as_of?(year) }
  end

  # True only once every member of the household has retired.
  def fully_retired_as_of?(year)
    users.any? && users.all? { |user| user.retired_as_of?(year) }
  end

  # Returns the year when the first household member retires
  def retirement_year
    users.filter_map(&:retirement_year).min
  end

  # Returns the year when the last household member retires (the whole
  # household is retired). The Income Projection uses this as its start year.
  def fully_retired_year
    users.filter_map(&:retirement_year).max
  end

  # def age(year = Time.zone.now.year)
  #   return 0 unless users.any? && users.first.birth_date
  #
  #   users.map { |user| user.age(year) }.max
  # end

  def milestone_years
    return [] unless users.any? && users.first.birth_date

    milestone_years = milestone_ages.map { |milestone_age| eldest_user.birth_year + milestone_age }.compact
    milestone_years.unshift Time.zone.now.year
    # TODO: consider adding life expectancy year as a milestone
    # milestone_years.push life_expectancy_year if life_expectancy_year
  end

  # TODO: make this customizable per household
  def milestone_ages
    DEFAULT_MILESTONE_AGES
  end

  def eldest_user
    @eldest_user ||= users.by_birth_year.limit(1).first
  end

  def terminal_year
    max_life_expectancy_year || (Time.zone.now.year + 50)
  end

  def user_ages_in_year(year)
    users.map { |u| u.age_in_year(year) }.join(', ')
  end
end
