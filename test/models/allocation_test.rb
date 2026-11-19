# == Schema Information
#
# Table name: allocations
#
#  id                 :integer          not null, primary key
#  avg_nominal_return :decimal(5, 4)    default(0.0), not null
#  description        :text
#  equity_pct         :decimal(5, 4)    not null
#  fixed_income_pct   :decimal(5, 4)    not null
#  name               :string
#  std_dev            :decimal(5, 4)    default(0.0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
require 'test_helper'

class AllocationTest < ActiveSupport::TestCase
  def setup
    @very_aggressive = allocations(:very_aggressive)
    @balanced = allocations(:balanced)
    @very_conservative = allocations(:very_conservative)
  end

  test 'valid with valid attributes' do
    assert @balanced.valid?
  end

  test 'allocation is invalid when equity_pct and fixed_income_pct do not sum to 1' do
    @balanced.equity_pct = 1.5
    assert_not @balanced.valid?
  end
end
