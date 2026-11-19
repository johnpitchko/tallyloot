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
  class Cpp < Benefit
    # CPP can start between 60-70, with actuarial adjustments
    EARLIEST_START_AGE = 60
    STANDARD_START_AGE = 65
    LATEST_START_AGE = 70

    # Adjustment factors per month
    EARLY_REDUCTION_PER_MONTH = 0.006  # 0.6% reduction per month before 65
    LATE_INCREASE_PER_MONTH = 0.007    # 0.7% increase per month after 65

    attribute :start_age, :integer, default: STANDARD_START_AGE
    attribute :inflation_indexed, :boolean, default: true

    validates :start_age, numericality: {
      greater_than_or_equal_to: EARLIEST_START_AGE,
      less_than_or_equal_to: LATEST_START_AGE,
    }

    def type_name = 'CPP'
    def government_benefit? = true
    def earliest_start_age = EARLIEST_START_AGE
    def latest_start_age = LATEST_START_AGE
    def default_start_age = STANDARD_START_AGE

    # CPP is always inflation-indexed regardless of user setting
    def inflation_indexed? = true

    # Adjust benefit amount based on early/late start
    def adjustment_factor
      months_from_standard = (start_age - STANDARD_START_AGE) * 12

      if months_from_standard.negative?
        # Early: reduce by 0.6% per month
        1.0 + (months_from_standard * EARLY_REDUCTION_PER_MONTH)
      elsif months_from_standard.positive?
        # Late: increase by 0.7% per month
        1.0 + (months_from_standard * LATE_INCREASE_PER_MONTH)
      else
        1.0
      end
    end

    def adjusted_annual_amount
      (annual_amount * adjustment_factor).round
    end

    # Override to use adjusted amount
    def annual_amount_nominal(year, inflation_rate: nil)
      return 0 unless eligible_for_income?(year)

      inflate_amount(adjusted_annual_amount, year, inflation_rate)
    end
  end
end
