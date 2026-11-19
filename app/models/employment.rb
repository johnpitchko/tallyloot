# == Schema Information
#
# Table name: employments
#
#  id            :integer          not null, primary key
#  annual_income :integer          default(0), not null
#  currency_code :string           default("CAD"), not null
#  end_age       :integer          not null
#  label         :string
#  start_age     :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_employments_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Employment < ApplicationRecord
  include Inspectable

  belongs_to :user

  validates :annual_income, presence: true,
                            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :start_age, presence: true,
                        numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :end_age, presence: true,
                      numericality: { only_integer: true,
                                      greater_than_or_equal_to: ->(e) { e.start_age || 0 }, }
  validates :currency_code, presence: true

  attribute :annual_income, :integer, default: 0
  attribute :currency_code, :string, default: 'CAD'

  inspectable :label, :annual_income, :start_age, :end_age

  # Returns annual income if the user is between start_age and end_age in the given year.
  # Used to aggregate post-retirement earned income for OAS clawback calculations.
  def income_in_year(year)
    return 0 unless active_in_year?(year)

    annual_income
  end

  def active_in_year?(year)
    return false unless user

    age = user.age_in_year(year)
    age.between?(start_age, end_age)
  end
end
