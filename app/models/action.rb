# == Schema Information
#
# Table name: actions
#
#  id         :integer          not null, primary key
#  amount     :integer
#  cadence    :integer          default(1), not null
#  end_year   :integer
#  kind       :string
#  start_year :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :integer          not null
#  plan_id    :integer          not null
#
# Indexes
#
#  index_actions_on_account_id  (account_id)
#  index_actions_on_plan_id     (plan_id)
#
# Foreign Keys
#
#  account_id  (account_id => accounts.id)
#  plan_id     (plan_id => plans.id)
#
class Action < ApplicationRecord
  include Inspectable

  belongs_to :plan
  belongs_to :account, optional: true

  enum :kind, {
    contribution: 'contribution',
    withdrawal: 'withdrawal',
    purchase: 'purchase',
    income: 'income',
    pension: 'pension',
  }

  validates :cadence, numericality: { only_integer: true, greater_than: 0, less_than: 25 }

  scope :for_year, ->(year) { where(start_year: ..year).where('end_year IS NULL OR end_year >= ?', year) }
  scope :for_account, ->(account) { where(account: account) }

  inspectable :account, :kind, :amount, :cadence, :start_year, :end_year

  def self.total_amount
    sum(:amount)
  end

  # TODO: signs should be handled and verified when the Action is saved, not upon retrieval.
  # def signed_amount
  #   return nil if amount.nil?
  #
  #   case kind
  #   when 'withdrawal', 'purchase'
  #     -amount.abs
  #   else
  #     amount.abs
  #   end
  # end

  def active_years
    return [] if start_year.nil? || end_year.nil? || cadence.nil? || cadence <= 0

    (start_year..end_year).step(cadence).to_a
  end

  def active_in_year?(year)
    return false if start_year.nil? || end_year.nil? || cadence.nil? || cadence <= 0
    return false if year < start_year || year > end_year

    ((year - start_year) % cadence).zero?
  end
end
