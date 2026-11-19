# Encapsulates a CPP or OAS start-age change for the What If? page.
# Computes the break-even age internally; returns nil for #breakeven when the
# later-starting scenario never surpasses the earlier one within life expectancy.
class WhatIf
  module Adjustment
    class BenefitTiming
      def initialize(benefit, new_age, inflation_rate:)
        @benefit       = benefit
        @new_age       = new_age
        @inflation_rate = inflation_rate
      end

      def changed?
        @new_age != @benefit.start_age
      end

      def breakeven
        @breakeven ||= compute_breakeven
      end

      def type
        :info
      end

      def text
        label = benefit_label
        if @new_age > @benefit.start_age
          "#{label}: Delaying to age #{@new_age} raises your benefit. " \
            "This pays off if you live past age #{breakeven}."
        else
          "#{label}: Taking #{label} at age #{@new_age} gives more years of payments. " \
            "This pays off if you don't live past age #{breakeven}."
        end
      end

      private

      def benefit_label
        @benefit.is_a?(Benefit::Cpp) ? 'CPP' : 'OAS'
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def compute_breakeven
        original_age = @benefit.start_age
        user = @benefit.user

        alt_benefit = @benefit.dup
        alt_benefit.id = @benefit.id
        alt_benefit.start_age = @new_age
        alt_benefit.association(:user).target = user

        early_b, late_b = @new_age > original_age ? [@benefit, alt_benefit] : [alt_benefit, @benefit]

        early_cum = 0
        late_cum  = 0
        start_year = user.birth_year + [original_age, @new_age].min

        (start_year..user.life_expectancy_year).each do |year|
          early_cum += early_b.annual_amount_nominal(year, inflation_rate: @inflation_rate)
          late_cum  += late_b.annual_amount_nominal(year, inflation_rate: @inflation_rate)
          return user.age_in_year(year) if late_cum >= early_cum
        end

        nil
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
    end
  end
end
