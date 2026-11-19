class WhatIf
  module Adjustment
    class Glidepath
      def initialize(old_glidepath, new_glidepath)
        @old = old_glidepath
        @new = new_glidepath
      end

      def changed?
        @old.id != @new.id
      end

      def type
        :info
      end

      def text
        "Switching from #{@old.name} to #{@new.name} changes your projected returns. " \
          'More aggressive strategies project higher average growth but with greater year-to-year variability.'
      end
    end
  end
end
