class Scenario
  module Lever
    # The only record-scoped lever: it targets a specific account rather than a
    # person, so it carries account_id instead of relying on person_id.
    class AccountContribution < Base
      include ActiveSupport::NumberHelper

      attr_reader :account_id

      def initialize(value:, account_id:, person_id: nil)
        super(value: value, person_id: person_id)
        @account_id = account_id
      end

      def apply(draft)
        target = account(draft)
        target.contribution = value if target
      end

      def describe(draft)
        "Contribute #{number_to_currency(value, precision: 0)}/yr to #{account(draft)&.name}"
      end

      def to_h = super.merge('account_id' => account_id)

      def ==(other) = super && other.account_id == account_id
      alias eql? ==

      def hash = [self.class, account_id, value].hash

      private

      def account(draft) = draft.accounts.find { |a| a.id == account_id }
    end
  end
end
