class Scenario
  module Lever
    class RetirementAge < Base
      def apply(draft)
        draft.user(person_id).retirement_age = value
      end

      def describe(draft) = "#{person_name(draft)} retires at age #{value}"
    end
  end
end
