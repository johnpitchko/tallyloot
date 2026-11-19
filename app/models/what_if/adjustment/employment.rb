class WhatIf
  module Adjustment
    class Employment
      def initialize(employment, new_end_age:)
        @employment  = employment
        @new_end_age = new_end_age
      end

      def changed?
        @new_end_age != @employment.end_age
      end

      def type
        if @new_end_age > @employment.end_age then :success
        elsif @new_end_age < @employment.end_age then :danger
        else
          :info
        end
      end

      def text
        direction = @new_end_age > @employment.end_age ? 'extended' : 'reduced'
        "#{@employment.user.name}: Post-retirement work #{direction} to age #{@new_end_age}."
      end
    end
  end
end
