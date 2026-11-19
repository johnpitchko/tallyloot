# == Schema Information
#
# Table name: benefits
#
#  id                :integer          not null, primary key
#  annual_amount     :integer
#  inflation_indexed :boolean
#  name              :string
#  start_age         :integer
#  type              :string           default("Benefit::Custom"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :integer          not null
#
# Indexes
#
#  index_benefits_on_type     (type)
#  index_benefits_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Benefit
  class Oas < Benefit
    # OAS can start between 65-70 (cannot start early like CPP)
    EARLIEST_START_AGE = 65
    STANDARD_START_AGE = 65
    LATEST_START_AGE = 70

    # Delay increase: 0.6% per month after 65 (max 36% increase at 70)
    DELAY_INCREASE_PER_MONTH = 0.006

    attribute :start_age, :integer, default: STANDARD_START_AGE
    attribute :inflation_indexed, :boolean, default: true

    validates :start_age, numericality: {
      greater_than_or_equal_to: EARLIEST_START_AGE,
      less_than_or_equal_to: LATEST_START_AGE,
    }

    def type_name = 'OAS'
    def government_benefit? = true
    def earliest_start_age = EARLIEST_START_AGE
    def latest_start_age = LATEST_START_AGE
    def default_start_age = STANDARD_START_AGE

    # OAS is always inflation-indexed regardless of user setting
    def inflation_indexed? = true

    # Adjust benefit amount for delayed start
    def adjustment_factor
      months_delayed = (start_age - STANDARD_START_AGE) * 12
      return 1.0 if months_delayed <= 0

      1.0 + (months_delayed * DELAY_INCREASE_PER_MONTH)
    end

    def adjusted_annual_amount
      (annual_amount * adjustment_factor).round
    end

    # Override to use adjusted amount
    # TODO: Consider OAS clawback for high-income individuals
    def annual_amount_nominal(year, inflation_rate: nil)
      return 0 unless eligible_for_income?(year)

      inflate_amount(adjusted_annual_amount, year, inflation_rate)
    end
  end
end
