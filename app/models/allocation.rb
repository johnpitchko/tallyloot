# == Schema Information
#
# Table name: allocations
#
#  id                 :integer          not null, primary key
#  avg_nominal_return :decimal(5, 4)    default(0.0), not null
#  description        :text
#  equity_pct         :decimal(5, 4)    not null
#  fixed_income_pct   :decimal(5, 4)    not null
#  name               :string
#  std_dev            :decimal(5, 4)    default(0.0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class Allocation < ApplicationRecord
  include Inspectable

  inspectable :name, :equity_pct, :fixed_income_pct

  validates :equity_pct, :fixed_income_pct, :avg_nominal_return, presence: true,
                                                                 numericality: {
                                                                   greater_than_or_equal_to: 0,
                                                                   less_than_or_equal_to: 1,
                                                                 }

  validate :equity_pct_and_fixed_income_pct_sum_to_one

  DEFAULT_ALLOCATION_NAME = 'Aggressive'.freeze

  def self.default
    find_by!(name: DEFAULT_ALLOCATION_NAME)
  end

  def real_return(inflation_rate)
    return avg_nominal_return if inflation_rate.zero?

    ((1 + avg_nominal_return) / (1 + inflation_rate)) - 1
  end

  private

  def equity_pct_and_fixed_income_pct_sum_to_one
    return false if equity_pct.blank? || fixed_income_pct.blank?

    return if (equity_pct + fixed_income_pct).round(4) == 1.0.to_d

    errors.add(:base, 'Equity and Fixed Income percentages must sum to 100%')
  end
end
