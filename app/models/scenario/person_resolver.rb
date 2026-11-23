class Scenario
  # Maps the person references a language model emits ("self", "spouse", or a
  # first name) onto real User records.
  #
  # Database IDs are never sent to or accepted from the model. Every raise here
  # becomes a clarifying question rather than an error page.
  class PersonResolver
    class AmbiguousPersonError < StandardError; end

    SELF_REFERENCE = 'self'.freeze
    SPOUSE_REFERENCE = 'spouse'.freeze

    def initialize(household, current_user)
      @household = household
      @current_user = current_user
    end

    def resolve(reference)
      normalized = reference.to_s.strip.downcase
      raise AmbiguousPersonError, 'No person was specified.' if normalized.blank?

      case normalized
      when SELF_REFERENCE then @current_user
      when SPOUSE_REFERENCE then spouse
      else by_name(reference)
      end
    end

    private

    def members = @members ||= @household.users.to_a

    def spouse
      others = members.reject { |u| u.id == @current_user.id }
      if others.empty?
        raise AmbiguousPersonError, 'There is no spouse in this household.'
      elsif others.size > 1
        raise AmbiguousPersonError,
              "This household has more than one other member. Which one did you mean: #{names(others)}?"
      end

      others.first
    end

    def by_name(reference)
      matches = members.select { |u| u.name.to_s.casecmp?(reference.to_s.strip) }
      if matches.empty?
        raise AmbiguousPersonError, "I couldn't find #{reference} in this household. Members are: #{names(members)}."
      elsif matches.size > 1
        raise AmbiguousPersonError, "More than one household member is named #{reference}."
      end

      matches.first
    end

    def names(users) = users.map(&:name).join(', ')
  end
end
