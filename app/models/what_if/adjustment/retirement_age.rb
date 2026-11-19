class WhatIf
  module Adjustment
    class RetirementAge
      def initialize(user, new_age)
        @user    = user
        @new_age = new_age
      end

      def changed?
        @new_age != @user.retirement_age
      end

      def type
        @new_age > @user.retirement_age ? :success : :danger
      end

      def text
        diff  = @new_age - @user.retirement_age
        years = diff.abs
        yr    = years == 1 ? 'year' : 'years'

        if diff.positive?
          "#{@user.name}: Retiring #{years} #{yr} later adds more contribution years " \
            'and shortens the period you draw from savings.'
        else
          "#{@user.name}: Retiring #{years} #{yr} earlier means fewer contribution " \
            'years and a longer period drawing from savings.'
        end
      end
    end
  end
end
