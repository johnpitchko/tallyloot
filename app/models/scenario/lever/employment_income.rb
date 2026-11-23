class Scenario
  module Lever
    class EmploymentIncome < Base
      include ActiveSupport::NumberHelper

      def apply(draft)
        employment = draft.user(person_id)&.employment
        employment.annual_income = value if employment
      end

      def describe(draft)
        "#{person_name(draft)} earns #{number_to_currency(value, precision: 0)}/yr in post-retirement work"
      end
    end
  end
end
