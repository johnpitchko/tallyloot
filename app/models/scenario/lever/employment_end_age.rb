class Scenario
  module Lever
    class EmploymentEndAge < Base
      def apply(draft)
        employment = draft.user(person_id)&.employment
        employment.end_age = value if employment
      end

      def describe(draft) = "#{person_name(draft)} works until age #{value}"
    end
  end
end
