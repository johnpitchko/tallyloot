# == Schema Information
#
# Table name: scenarios
#
#  id                  :integer          not null, primary key
#  clarifying_question :text
#  confirmed_at        :datetime
#  confirmed_levers    :json             not null
#  parsed_levers       :json             not null
#  raw_input           :text             not null
#  status              :string           default("parsed"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  household_id        :integer          not null
#
# Indexes
#
#  index_scenarios_on_household_id  (household_id)
#  index_scenarios_on_status        (status)
#
# Foreign Keys
#
#  household_id  (household_id => households.id)
#

# A single natural-language what-if question and its lifecycle.
#
# Holds what the user typed, what the model extracted from it, and what the
# user actually confirmed. The gap between parsed_levers and confirmed_levers
# is the extraction-accuracy metric.
#
# Nothing here is written to the user's profile. A Scenario is a staging record.
class Scenario < ApplicationRecord
  include Inspectable

  MAX_INPUT_LENGTH = 500

  belongs_to :household

  enum :status, {
    parsed: 'parsed',
    clarifying: 'clarifying',
    confirmed: 'confirmed',
    rejected: 'rejected',
  }

  validates :raw_input, presence: true, length: { maximum: MAX_INPUT_LENGTH }

  inspectable :raw_input, :status

  def confirm!(levers)
    update!(confirmed_levers: levers, status: :confirmed, confirmed_at: Time.current)
  end
end
