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
  class Rrsp < Account
    FORCED_CONVERSION_AGE = 71

    attribute :conversion_age, :integer, default: FORCED_CONVERSION_AGE

    validates :conversion_age,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 55,
                less_than_or_equal_to: FORCED_CONVERSION_AGE,
              }

    def type_name = 'RRSP/RRIF'
    def taxable? = true
    def conversion_age? = true

    def conversion_year
      user.birth_year + conversion_age
    end

    def converted_as_of?(year)
      year >= conversion_year
    end

    def minimum_withdrawal?(year) = converted_as_of?(year)

    def minimum_withdrawal_rate(age)
      PRESCRIBED_WITHDRAWAL_RATES[age] || cra_formula_rate(age)
    end

    def can_withdraw?(year)
      converted_as_of?(year) && user.retired_as_of?(year)
    end

    private

    def cra_formula_rate(age)
      return PRESCRIBED_WITHDRAWAL_RATES[95] if age >= 95

      (1.0 / (90 - age)).round(4)
    end
  end
end
