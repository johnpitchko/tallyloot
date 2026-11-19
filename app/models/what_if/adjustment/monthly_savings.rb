class WhatIf
  module Adjustment
    class MonthlySavings
      include ActiveSupport::NumberHelper

      def initialize(user, delta)
        @user  = user
        @delta = delta
      end

      def changed?
        @delta != 0
      end

      def type
        @delta.positive? ? :success : :danger
      end

      def text
        direction = @delta.positive? ? 'more' : 'less'
        "#{@user.name}: Saving #{number_to_currency(@delta.abs, precision: 0)}/mo #{direction} has an outsized " \
          'long-term impact through compounding — small consistent changes add up significantly over time.'
      end
    end
  end
end
