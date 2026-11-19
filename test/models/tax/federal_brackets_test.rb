require 'test_helper'

module Tax
  class FederalBracketsTest < ActiveSupport::TestCase
    test 'returns zero tax for zero income' do
      brackets = FederalBrackets.new(year: 2024)
      assert_equal 0, brackets.tax_on(0)
    end

    test 'returns zero tax for negative income' do
      brackets = FederalBrackets.new(year: 2024)
      assert_equal 0, brackets.tax_on(-1000)
    end

    test 'returns zero tax for income below basic personal amount' do
      brackets = FederalBrackets.new(year: 2024)
      assert_equal 0, brackets.tax_on(brackets.basic_personal_amount - 1)
    end

    test 'applies 15% rate on income just above basic personal amount' do
      brackets = FederalBrackets.new(year: 2024)
      income = brackets.basic_personal_amount + 10_000
      expected = (10_000 * 0.15).round
      assert_equal expected, brackets.tax_on(income)
    end

    test 'correctly calculates tax crossing multiple brackets' do
      brackets = FederalBrackets.new(year: 2024)
      # $120,000 income in 2024
      # Net taxable: 120,000 - 15,705 = 104,295
      # Bracket 1: 55,867 * 0.15 = 8,380.05
      # Bracket 2: (104,295 - 55,867) * 0.205 = 48,428 * 0.205 = 9,927.74
      # Total: ~18,307
      result = brackets.tax_on(120_000)
      assert_in_delta 18_308, result, 5
    end

    test 'inflates basic personal amount for future years' do
      brackets_2024 = FederalBrackets.new(year: 2024, inflation_rate: 0.02)
      brackets_2034 = FederalBrackets.new(year: 2034, inflation_rate: 0.02)
      assert brackets_2034.basic_personal_amount > brackets_2024.basic_personal_amount
    end

    test 'inflates bracket thresholds for future years' do
      brackets_2024 = FederalBrackets.new(year: 2024, inflation_rate: 0.02)
      brackets_2034 = FederalBrackets.new(year: 2034, inflation_rate: 0.02)
      assert brackets_2034.brackets[1][:threshold] > brackets_2024.brackets[1][:threshold]
    end

    test 'uses base year brackets without inflation adjustment for past years' do
      brackets = FederalBrackets.new(year: 2020, inflation_rate: 0.02)
      assert_equal FederalBrackets::BASE_BASIC_PERSONAL_AMOUNT, brackets.basic_personal_amount
    end

    test 'quebec residents receive the 16.5 percent federal abatement' do
      federal = Tax::FederalBrackets.new(year: 2024, inflation_rate: 0.0)
      quebec  = Tax::FederalBrackets.new(year: 2024, inflation_rate: 0.0, province: 'QC')

      assert_equal (federal.tax_on(80_000) * (1 - 0.165)).round, quebec.tax_on(80_000)
    end

    test 'non-quebec residents receive no abatement' do
      federal = Tax::FederalBrackets.new(year: 2024, inflation_rate: 0.0)
      ontario = Tax::FederalBrackets.new(year: 2024, inflation_rate: 0.0, province: 'ON')

      assert_equal federal.tax_on(80_000), ontario.tax_on(80_000)
    end
  end
end
