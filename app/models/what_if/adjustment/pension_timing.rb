# Encapsulates a DB pension start-age change for the What If? page.
#
# Colour logic:
#   :warning — no actuarial rates configured (comparison is meaningless)
#   :warning — delay won't pay off within projected lifetime
#   :info    — tradeoff with a clear break-even age
#
class WhatIf
  module Adjustment
    class PensionTiming
      include ActiveSupport::NumberHelper

      def initialize(pension, new_start_age, inflation_rate:)
        @pension        = pension
        @new_start_age  = new_start_age
        @inflation_rate = inflation_rate
      end

      def changed?
        @new_start_age != @pension.start_age
      end

      def type
        return :warning unless actuarial_rates?

        breakeven ? :info : :warning
      end

      def text
        return no_rates_text unless actuarial_rates?

        delayed? ? delay_text : early_text
      end

      private

      def actuarial_rates?
        @pension.early_reduction_rate.present? || @pension.late_increase_rate.present?
      end

      def delayed?
        @new_start_age > @pension.start_age
      end

      def years
        (@new_start_age - @pension.start_age).abs
      end

      def yr
        years == 1 ? 'year' : 'years'
      end

      def early_p
        @early_p ||= @pension.dup.tap { |d| d.start_age = [@pension.start_age, @new_start_age].min }
      end

      def late_p
        @late_p ||= @pension.dup.tap { |d| d.start_age = [@pension.start_age, @new_start_age].max }
      end

      def annual_diff
        @annual_diff ||= (late_p.adjusted_annual_amount - early_p.adjusted_annual_amount).abs
      end

      def pct_diff
        @pct_diff ||= ((annual_diff.to_f / early_p.adjusted_annual_amount) * 100).round(1)
      end

      def breakeven
        @breakeven ||= compute_breakeven
      end

      def compute_breakeven
        user = @pension.user
        early_cum = 0
        late_cum  = 0
        start_year = user.birth_year + [@pension.start_age, @new_start_age].min

        (start_year..user.life_expectancy_year).each do |year|
          early_cum += early_p.annual_amount_nominal(year, inflation_rate: @inflation_rate)
          late_cum  += late_p.annual_amount_nominal(year, inflation_rate: @inflation_rate)
          return user.age_in_year(year) if late_cum >= early_cum
        end

        nil
      end

      def beyond_life_expectancy_breakeven
        early_amt = @pension.adjusted_annual_amount.to_f
        late_amt = @pension.dup.tap { |d| d.start_age = @new_start_age }.adjusted_annual_amount.to_f
        years_missed = @new_start_age - @pension.start_age
        head_start  = early_amt * years_missed
        annual_gain = late_amt - early_amt
        return '?' if annual_gain <= 0

        @pension.start_age + (head_start / annual_gain).ceil
      end

      def no_rates_text
        "#{@pension.name}: No actuarial rates are configured, so earlier collection " \
          'always projects as better. Add early/late adjustment rates in pension settings ' \
          'for a more accurate comparison.'
      end

      # rubocop:disable Metrics/MethodLength
      def delay_text
        diff_str = "#{number_to_currency(annual_diff, precision: 0)}/yr (+#{pct_diff}%)"
        if breakeven
          "#{@pension.name}: Delaying #{years} #{yr} raises annual payments by #{diff_str}. " \
            "This pays off if you live past age #{breakeven}."
        else
          user = @pension.user
          "#{@pension.name}: Delaying #{years} #{yr} raises annual payments by #{diff_str}, " \
            "but the higher rate doesn't fully recoup the missed payments within your projected " \
            "lifetime (life expectancy age #{user.life_expectancy}). " \
            "You'd need to live past age #{beyond_life_expectancy_breakeven} for this to pay off."
        end
      end

      def early_text
        diff_str = "#{number_to_currency(annual_diff, precision: 0)}/yr (-#{pct_diff}%)"
        if breakeven
          "#{@pension.name}: Collecting #{years} #{yr} early reduces annual payments by #{diff_str}. " \
            "The extra years of payments recoup the lower rate by age #{breakeven}."
        else
          user = @pension.user
          "#{@pension.name}: Collecting #{years} #{yr} early reduces annual payments by #{diff_str}. " \
            'The extra years of payments offset the lower rate within your projected lifetime ' \
            "(life expectancy age #{user.life_expectancy})."
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
