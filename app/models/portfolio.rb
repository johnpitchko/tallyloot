# == Schema Information
#
# Table name: portfolios
#
#  id                     :integer          not null, primary key
#  inflation_rate         :decimal(5, 2)
#  spending_smile_enabled :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  glidepath_id           :integer          not null
#  household_id           :integer          not null
#
# Indexes
#
#  index_portfolios_on_glidepath_id  (glidepath_id)
#  index_portfolios_on_household_id  (household_id)
#
# Foreign Keys
#
#  glidepath_id  (glidepath_id => glidepaths.id)
#  household_id  (household_id => households.id)
#
class Portfolio < ApplicationRecord
  include Inspectable

  belongs_to :glidepath
  belongs_to :household

  has_many :users, through: :household
  has_many :accounts, through: :users

  before_validation :assign_default_glidepath, on: :create

  validates :inflation_rate, presence: true,
                             numericality: { greater_than: 0, less_than_or_equal_to: 100 }

  attribute :inflation_rate, :decimal, default: 0.02
  attribute :spending_smile_enabled, :boolean, default: false

  inspectable :inflation_rate, :glidepath

  delegate :nominal_return_for_age, to: :glidepath

  def spending_smile_for(user)
    SpendingSmile.new(
      retirement_age: user.retirement_age,
      terminal_age: user.life_expectancy,
      enabled: spending_smile_enabled?
    )
  end

  def real_return_for_age(age)
    nominal = nominal_return_for_age(age)
    ((1 + nominal) / (1 + inflation_rate)) - 1
  end

  private

  def assign_default_glidepath
    self.glidepath ||= Glidepath.default
  end
end
