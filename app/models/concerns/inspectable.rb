# This module provides a way to customize the `#inspect` output for ActiveRecord models, allowing you to specify which
# attributes should be displayed. It formats values appropriately, handling types like BigDecimal and String for better
# readability.
#
# To implement, include this module in your ActiveRecord models and add the `inspectable` method to declare which
# attributes should be included in the inspect output.
#
# # Example usage:
#
# ```ruby
# class User < ApplicationRecord
#
# include Inspectable
#  inspectable :email_address, :name
# end
#
# User.first.inspect
# =>
# ```
module Inspectable
  extend ActiveSupport::Concern

  included do
    # Defines which attributes will be shown in the inspect output
    class_attribute :inspect_keys, instance_accessor: false, default: []
  end

  class_methods do
    # Declare inspectable attributes
    #
    # Example:
    #   inspectable :name, :status
    def inspectable(*keys)
      self.inspect_keys = keys.map(&:to_sym)
    end
  end

  # Override the default inspect output for the class
  def inspect
    attributes_string = self.class.inspect_keys.map do |key|
      value = send(key)
      "#{key}: #{format_inspect_value(value)}"
    end.join(', ')

    "#<#{self.class.name} #{attributes_string}>"
  end

  private

  # Formats each value for display
  def format_inspect_value(value)
    case value
    when BigDecimal
      value.to_f
    when String
      value.inspect # Adds quotes around strings
    when NilClass
      'nil'
    else
      value.respond_to?(:to_s) ? value.to_s : value.inspect
    end
  end
end
