class Scenario
  module Lever
    # Shared behaviour for every lever.
    #
    # person_id is an integer already resolved by Scenario::PersonResolver.
    # Levers never see the model's "self" / "spouse" references. Household-scope
    # levers pass person_id: nil.
    class Base
      attr_reader :person_id, :value

      def initialize(value:, person_id: nil)
        @person_id = person_id
        @value = value
      end

      # Mutate the draft. Subclasses must implement.
      def apply(_draft) = raise NotImplementedError, "#{self.class} must implement #apply"

      # Plain-English description for the confirmation UI. Subclasses must implement.
      def describe(_draft) = raise NotImplementedError, "#{self.class} must implement #describe"

      # Stable identifier used in the LLM schema and in persisted JSON.
      def self.key = name.demodulize.underscore

      delegate :key, to: :class

      def to_h = { 'lever' => key, 'person_id' => person_id, 'value' => value }

      def ==(other)
        other.instance_of?(self.class) && other.person_id == person_id && other.value == value
      end
      alias eql? ==

      def hash = [self.class, person_id, value].hash

      private

      def person_name(draft) = draft.user(person_id)&.name
    end
  end
end
