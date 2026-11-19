# == Schema Information
#
# Table name: benefits
#
#  id                :integer          not null, primary key
#  annual_amount     :integer
#  inflation_indexed :boolean
#  name              :string
#  start_age         :integer
#  type              :string           default("Benefit::Custom"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :integer          not null
#
# Indexes
#
#  index_benefits_on_type     (type)
#  index_benefits_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Benefit < ApplicationRecord
  def self.model_name
    ActiveModel::Name.new(self, nil, 'Benefit')
  end

  include Inspectable

  inspectable :annual_amount, :name, :start_age

  belongs_to :user
  has_one :household, through: :user
  has_one :portfolio, through: :household

  validates :name, :annual_amount, :start_age, presence: true
  validates :annual_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :start_age, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 120 }

  attribute :annual_amount, :integer, default: 0
  attribute :inflation_indexed, :boolean, default: false

  # Available benefit types for forms
  TYPES = %w[
    Benefit::Cpp
    Benefit::Oas
    Benefit::Custom
  ].freeze

  def self.type_options
    TYPES.map { |t| [t.constantize.new.type_name, t] }
  end

  # Subclass interface - override in subclasses as needed
  def type_name
    raise NotImplementedError, "#{self.class} must implement #type_name"
  end

  def government_benefit? = false
  def inflation_indexed? = inflation_indexed
  def earliest_start_age = 0
  def latest_start_age = 120
  def default_start_age = 65

  def start_year
    return nil if start_age.nil? || user.birth_date.nil?

    user.birth_year + start_age
  end

  def income_eligible?(year)
    return false if start_year.nil? || annual_amount.nil?

    year >= start_year
  end

  def annual_amount_nominal(year, inflation_rate: nil)
    return 0 unless eligible_for_income?(year)
    return annual_amount unless inflation_indexed?

    inflate_amount(annual_amount, year, inflation_rate)
  end

  private

  def eligible_for_income?(year)
    annual_amount.present? && income_eligible?(year) && start_year.present?
  end

  def inflate_amount(amount, year, rate = nil)
    rate ||= portfolio&.inflation_rate || 0.02
    years = year - start_year
    (amount * ((1 + rate)**years)).round
  end
end
