require 'test_helper'

module Period
  class TaxEstimateTest < ActiveSupport::TestCase
    test 'effective_rate is zero when taxable income is zero' do
      estimate = TaxEstimate.new(taxable_income: 0, federal_tax: 0)
      assert_equal 0.0, estimate.effective_rate
    end

    test 'effective_rate calculates correctly' do
      estimate = TaxEstimate.new(taxable_income: 100_000, federal_tax: 20_000)
      assert_in_delta 0.2, estimate.effective_rate, 0.0001
    end

    test 'estimated_tax sums federal and provincial' do
      estimate = TaxEstimate.new(taxable_income: 100_000, federal_tax: 15_000, provincial_tax: 8_000)
      assert_equal 23_000, estimate.estimated_tax
    end

    test 'provincial_tax defaults to zero' do
      estimate = TaxEstimate.new(taxable_income: 80_000, federal_tax: 12_000)
      assert_equal 0, estimate.provincial_tax
      assert_equal 12_000, estimate.estimated_tax
    end

    test 'exposes taxable_income, federal_tax, provincial_tax' do
      estimate = TaxEstimate.new(taxable_income: 80_000, federal_tax: 12_000, provincial_tax: 7_000)
      assert_equal 80_000, estimate.taxable_income
      assert_equal 12_000, estimate.federal_tax
      assert_equal 7_000, estimate.provincial_tax
    end
  end
end
