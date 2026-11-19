# == Schema Information
#
# Table name: glidepath_steps
#
#  id            :integer          not null, primary key
#  start_age     :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  allocation_id :integer          not null
#  glidepath_id  :integer          not null
#
# Indexes
#
#  index_glidepath_steps_on_allocation_id  (allocation_id)
#  index_glidepath_steps_on_glidepath_id   (glidepath_id)
#
# Foreign Keys
#
#  allocation_id  (allocation_id => allocations.id)
#  glidepath_id   (glidepath_id => glidepaths.id)
#
require 'test_helper'

class GlidepathStepTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
