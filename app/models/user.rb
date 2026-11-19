# == Schema Information
#
# Table name: users
#
#  id              :integer          not null, primary key
#  birth_date      :date             not null
#  life_expectancy :integer          default(82), not null
#  name            :string
#  retirement_age  :integer          default(65), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  household_id    :integer
#
# Indexes
#
#  index_users_on_household_id  (household_id)
#
# Foreign Keys
#
#  household_id  (household_id => households.id)
#
class User < ApplicationRecord
  include Inspectable

  scope :by_birth_year, -> { order(birth_date: :asc) }

  belongs_to :household
  has_many :accounts, dependent: :destroy
  has_many :pensions, dependent: :destroy
  has_many :benefits, dependent: :destroy
  has_one :employment, dependent: :destroy
  has_one :portfolio, through: :household

  # Allows letters (including accented), spaces, hyphens, apostrophes
  NAME_FORMAT = /\A[\p{L}\s\-']+\z/
  NAME_FORMAT_MESSAGE = 'can only contain letters, spaces, hyphens, and apostrophes'.freeze
  private_constant :NAME_FORMAT, :NAME_FORMAT_MESSAGE

  validates :name, format: { with: NAME_FORMAT, message: NAME_FORMAT_MESSAGE }, allow_blank: true
  validates :birth_date, presence: true
  validate :birth_date_within_reasonable_range
  validates :life_expectancy, presence: true,
                              numericality: { only_integer: true, greater_than_or_equal_to: 0,
                                              less_than_or_equal_to: 120, }

  validates :retirement_age, presence: true,
                             numericality: { only_integer: true, greater_than_or_equal_to: 0,
                                             less_than_or_equal_to: 120, }

  attribute :life_expectancy, :integer, default: 82
  attribute :retirement_age, :integer, default: 65

  def age
    return 0 if birth_date.blank?

    today = Date.current
    years = today.year - birth_date.year
    years -= 1 if today < birth_date.change(year: today.year)
    years
  end

  def age_in_year(year = Time.zone.now.year)
    return 0 if birth_date.blank?

    year - birth_date.year
  end

  def birth_year
    birth_date.year
  end

  def life_expectancy_year
    return nil if life_expectancy.blank? || birth_date.blank?

    birth_year + life_expectancy
  end

  def inflation_rate
    portfolio.inflation_rate || 0.02
  end

  def retired_as_of?(year)
    return false if birth_date.blank? || retirement_age.blank?

    year >= retirement_year
  end

  def retirement_year
    return if birth_date.blank? || retirement_age.blank?

    birth_year + retirement_age
  end

  private

  # rubocop:disable Metrics/AbcSize
  def birth_date_within_reasonable_range
    return if birth_date.blank?

    if birth_date > Date.current
      errors.add(:birth_date, 'cannot be in the future')
    elsif birth_date < 120.years.ago.to_date
      errors.add(:birth_date, 'is too far in the past')
    elsif birth_date > 18.years.ago.to_date
      errors.add(:birth_date, 'must be at least 18 years old')
    end
  end
  # rubocop:enable Metrics/AbcSize
end
