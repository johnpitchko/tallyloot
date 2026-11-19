# == Schema Information
#
# Table name: accounts
#
#  id                      :integer          not null, primary key
#  balance                 :integer
#  contribution            :integer          default(0)
#  conversion_age          :integer
#  name                    :string
#  provincial_jurisdiction :string
#  type                    :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  user_id                 :integer          not null
#
# Indexes
#
#  index_accounts_on_type     (type)
#  index_accounts_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Account < ApplicationRecord
  def self.model_name
    ActiveModel::Name.new(self, nil, 'Account')
  end

  belongs_to :user
  has_one :household, through: :user
  has_one :portfolio, through: :household

  attribute :balance, :integer, default: 0
  attribute :contribution, :integer, default: 0

  validates :name, presence: true
  validates :balance, numericality: true
  validates :contribution, numericality: { greater_than_or_equal_to: 0 }

  # Available account types for forms
  TYPES = %w[
    Account::Tfsa
    Account::Rrsp
    Account::Lira
    Account::Fhsa
    Account::NonRegistered
  ].freeze

  # CRA prescribed RRIF minimum withdrawal rates for ages 71+ (2025)
  # https://www.canada.ca/en/revenue-agency/services/tax/individuals/topics/rrsps-related-plans/registered-retirement-income-fund-rrif.html
  # For ages under 71, CRA uses the formula: 1 / (90 - age)
  PRESCRIBED_WITHDRAWAL_RATES = {
    71 => 0.0528, 72 => 0.0540, 73 => 0.0553, 74 => 0.0567,
    75 => 0.0582, 76 => 0.0598, 77 => 0.0617, 78 => 0.0636, 79 => 0.0658,
    80 => 0.0682, 81 => 0.0708, 82 => 0.0738, 83 => 0.0771, 84 => 0.0808,
    85 => 0.0851, 86 => 0.0899, 87 => 0.0955, 88 => 0.1021, 89 => 0.1099,
    90 => 0.1192, 91 => 0.1306, 92 => 0.1449, 93 => 0.1634, 94 => 0.1879,
    95 => 0.2000,
  }.freeze

  # Subclasses must implement these
  def taxable?
    raise NotImplementedError, "#{self.class} must implement #taxable?"
  end

  def type_name
    raise NotImplementedError, "#{self.class} must implement #type_name"
  end

  # Default implementations (override in subclasses as needed)
  def requires_jurisdiction? = false
  def allows_contributions? = true
  def minimum_withdrawal?(_year) = false
  def maximum_withdrawal?(_year) = false
  def minimum_withdrawal_rate(_age) = 0
  def maximum_withdrawal_rate(_age) = nil

  # Withdrawal priority for goal-based allocation (lower = withdraw first)
  # Priority 1: Non-registered (taxable but flexible)
  # Priority 2: Registered accounts (RRSP/RRIF/LIF)
  # Priority 3: Tax-free accounts (TFSA) - preserve growth
  def withdrawal_priority = 2

  def converted_as_of?(_year) = false
  def conversion_age? = false

  def can_withdraw?(year)
    user.retired_as_of?(year)
  end

  PROVINCIAL_JURISDICTIONS = %w[AB BC MB NB NL NS NT NU ON PE QC SK YT].freeze

  def self.type_options
    TYPES.map { |t| [t.constantize.new.type_name, t] }
  end

  def self.jurisdiction_options
    PROVINCIAL_JURISDICTIONS.map { |j| [j, j] }
  end
end
