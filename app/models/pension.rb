# == Schema Information
#
# Table name: pensions
#
#  id                    :integer          not null, primary key
#  annual_amount         :decimal(10, 2)   default(0.0), not null
#  description           :string
#  early_reduction_rate  :decimal(5, 4)
#  inflation_indexed     :boolean
#  late_increase_rate    :decimal(5, 4)
#  name                  :string
#  normal_retirement_age :integer          default(65)
#  start_age             :integer          not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  user_id               :integer          not null
#
# Indexes
#
#  index_pensions_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Pension < ApplicationRecord
  include Inspectable

  inspectable :annual_amount, :name, :start_age

  belongs_to :user
  has_one :household, through: :user
  has_one :plan, through: :household
  has_one :portfolio, through: :household

  validates :name, :annual_amount, :start_age, presence: true
  validates :early_reduction_rate, :late_increase_rate,
            numericality: { greater_than_or_equal_to: 0, less_than: 1 }, allow_nil: true

  def early_reduction_rate_pct
    early_reduction_rate.present? ? (early_reduction_rate.to_f * 100).round(2) : nil
  end

  def early_reduction_rate_pct=(value)
    self.early_reduction_rate = value.present? ? value.to_f / 100 : nil
  end

  def late_increase_rate_pct
    late_increase_rate.present? ? (late_increase_rate.to_f * 100).round(2) : nil
  end

  def late_increase_rate_pct=(value)
    self.late_increase_rate = value.present? ? value.to_f / 100 : nil
  end

  def start_year
    return nil if start_age.nil? || user.birth_date.nil?

    user.birth_year + start_age
  end

  def income_eligible?(year)
    return false if start_year.nil? || annual_amount.nil?

    year >= start_year
  end

  # rubocop:disable Metrics/AbcSize
  def adjustment_factor
    nra = normal_retirement_age || 65
    years_from_nra = start_age - nra

    if years_from_nra.negative? && early_reduction_rate.present?
      1.0 - (early_reduction_rate.to_f * years_from_nra.abs)
    elsif years_from_nra.positive? && late_increase_rate.present?
      1.0 + (late_increase_rate.to_f * years_from_nra)
    else
      1.0
    end
  end
  # rubocop:enable Metrics/AbcSize

  def adjusted_annual_amount
    (annual_amount * adjustment_factor).round
  end

  # rubocop:disable Metrics/AbcSize
  def annual_amount_nominal(year, inflation_rate: nil)
    return 0 if annual_amount.nil? || !income_eligible?(year) || start_year.nil?

    inflation_rate ||= portfolio.inflation_rate
    base = adjusted_annual_amount

    return base unless inflation_indexed

    (base * ((1 + inflation_rate)**(year - start_year))).round
  end
  # rubocop:enable Metrics/AbcSize
end
