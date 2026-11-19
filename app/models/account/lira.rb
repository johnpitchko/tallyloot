# == Schema Information
#
# Table name: accounts
#
#  id                      :integer          not null, primary key
#  balance                 :integer
#  contribution            :integer          default(0)
#  conversion_age          :integer
#  name                    :string
#  provincial_jurisdiction :string
#  type                    :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  user_id                 :integer          not null
#
# Indexes
#
#  index_accounts_on_type     (type)
#  index_accounts_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Account
  class Lira < Account
    PROVINCIAL_MIN_CONVERSION_AGES = {
      'AB' => 50, 'BC' => 55, 'MB' => 55, 'NB' => 55, 'NL' => 55,
      'NS' => 55, 'NT' => 55, 'NU' => 55, 'ON' => 55, 'PE' => 55,
      'QC' => 55, 'SK' => 55, 'YT' => 55,
    }.freeze
    FORCED_CONVERSION_AGE = 71

    attribute :conversion_age, :integer, default: FORCED_CONVERSION_AGE

    validates :provincial_jurisdiction, presence: true, inclusion: { in: Account::PROVINCIAL_JURISDICTIONS }
    validates :conversion_age,
              presence: true,
              numericality: { only_integer: true, less_than_or_equal_to: FORCED_CONVERSION_AGE }
    validate :conversion_age_meets_provincial_minimum

    def type_name = 'LIRA/LIF'
    def taxable? = true
    def requires_jurisdiction? = true
    def conversion_age? = true

    def minimum_conversion_age
      PROVINCIAL_MIN_CONVERSION_AGES[provincial_jurisdiction] || 55
    end

    def conversion_year
      user.birth_year + conversion_age
    end

    def converted_as_of?(year)
      year >= conversion_year
    end

    def allows_contributions? = false

    def minimum_withdrawal?(year) = converted_as_of?(year)
    def maximum_withdrawal?(year) = converted_as_of?(year)

    def minimum_withdrawal_rate(age)
      PRESCRIBED_WITHDRAWAL_RATES[age] || cra_formula_rate(age)
    end

    def maximum_withdrawal_rate(_age)
      # Simplified - real calculation varies by province and CANSIM rates
      # TODO: Implement province-specific maximums
      0.10
    end

    def can_withdraw?(year)
      converted_as_of?(year) && user.retired_as_of?(year)
    end

    private

    def cra_formula_rate(age)
      return PRESCRIBED_WITHDRAWAL_RATES[95] if age >= 95

      (1.0 / (90 - age)).round(4)
    end

    def conversion_age_meets_provincial_minimum
      return unless conversion_age && provincial_jurisdiction
      return unless conversion_age < minimum_conversion_age

      errors.add(:conversion_age, "must be at least #{minimum_conversion_age} for #{provincial_jurisdiction}")
    end
  end
end
