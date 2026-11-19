# == Schema Information
#
# Table name: portfolios
#
#  id                     :integer          not null, primary key
#  inflation_rate         :decimal(5, 2)
#  spending_smile_enabled :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  glidepath_id           :integer          not null
#  household_id           :integer          not null
#
# Indexes
#
#  index_portfolios_on_glidepath_id  (glidepath_id)
#  index_portfolios_on_household_id  (household_id)
#
# Foreign Keys
#
#  glidepath_id  (glidepath_id => glidepaths.id)
#  household_id  (household_id => households.id)
#
require 'test_helper'

class PortfolioTest < ActiveSupport::TestCase
end
