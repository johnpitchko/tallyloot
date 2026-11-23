class Scenario
  module Lever
    class LifeExpectancy < Base
      def apply(draft)
        draft.user(person_id).life_expectancy = value
      end

      def describe(draft) = "#{person_name(draft)} lives to age #{value}"
    end
  end
end
