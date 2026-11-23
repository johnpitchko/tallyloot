class Scenario
  module Lever
    # A monthly savings delta, fanned out across a user's accounts.
    #
    # Mirrors WhatIf#accounts_params: annualise the delta, spread it evenly over
    # the accounts that already contribute, fall back to all of the user's
    # accounts when none do, and floor each result at zero.
    class MonthlySavings < Base
      include ActiveSupport::NumberHelper

      def apply(draft)
        targets = target_accounts(draft)
        return if targets.empty?

        per_account = ((value * 12).to_f / targets.size).round
        targets.each do |account|
          account.contribution = [account.contribution.to_i + per_account, 0].max
        end
      end

      def describe(draft)
        direction = value.negative? ? 'less' : 'more'
        "#{person_name(draft)} saves #{number_to_currency(value.abs, precision: 0)}/mo #{direction}"
      end

      private

      def target_accounts(draft)
        owned = draft.accounts.select { |a| a.user_id == person_id }
        contributing = owned.select { |a| a.contribution.to_i.positive? }
        contributing.presence || owned
      end
    end
  end
end
