require 'test_helper'

module Tax
  class ProvincialBracketsTest < ActiveSupport::TestCase
    test 'returns zero for nil province' do
      brackets = ProvincialBrackets.new(province: nil, year: 2024)
      assert_equal 0, brackets.tax_on(100_000)
    end

    test 'returns zero for unknown province code' do
      brackets = ProvincialBrackets.new(province: 'XX', year: 2024)
      assert_equal 0, brackets.tax_on(100_000)
    end

    test 'returns zero for zero income' do
      brackets = ProvincialBrackets.new(province: 'ON', year: 2024)
      assert_equal 0, brackets.tax_on(0)
    end

    test 'returns zero for income below basic personal amount' do
      brackets = ProvincialBrackets.new(province: 'ON', year: 2024)
      assert_equal 0, brackets.tax_on(brackets.basic_personal_amount - 1)
    end

    test 'supported? is true for known province' do
      assert ProvincialBrackets.new(province: 'ON', year: 2024).supported?
    end

    test 'supported? is false for nil province' do
      refute ProvincialBrackets.new(province: nil, year: 2024).supported?
    end

    test 'Ontario: correct tax on $100,000' do
      # Net taxable: 100_000 - 11_865 = 88_135
      # 5.05% on 51_446 = 2_598
      # 9.15% on (88_135 - 51_446) = 36_689 * 9.15% = 3_357
      # Basic tax ≈ 5_955
      # Surtax: 20% of (5_955 - 5_554) = 80
      # Total ≈ 6_035
      brackets = ProvincialBrackets.new(province: 'ON', year: 2024)
      assert_in_delta 6_035, brackets.tax_on(100_000), 5
    end

    test 'Alberta: correct tax on $100,000' do
      # Net taxable: 100_000 - 21_003 = 78_997
      # 10% on 78_997 = 7_900 (all in first bracket)
      brackets = ProvincialBrackets.new(province: 'AB', year: 2024)
      assert_in_delta 7_900, brackets.tax_on(100_000), 5
    end

    test 'Quebec: correct tax on $100,000' do
      # Net taxable: 100_000 - 17_183 = 82_817
      # 14% on 51_780 = 7_249
      # 19% on (82_817 - 51_780) = 31_037 * 19% = 5_897
      # Total ≈ 13_146
      brackets = ProvincialBrackets.new(province: 'QC', year: 2024)
      assert_in_delta 13_146, brackets.tax_on(100_000), 5
    end

    test 'all 13 provinces and territories are supported' do
      %w[AB BC MB NB NL NS NT NU ON PE QC SK YT].each do |province|
        brackets = ProvincialBrackets.new(province: province, year: 2024)
        assert brackets.supported?, "#{province} should be supported"
        assert brackets.tax_on(80_000) >= 0, "#{province} should return non-negative tax"
      end
    end

    test 'inflates thresholds for future years' do
      brackets_2024 = ProvincialBrackets.new(province: 'ON', year: 2024, inflation_rate: 0.02)
      brackets_2034 = ProvincialBrackets.new(province: 'ON', year: 2034, inflation_rate: 0.02)
      assert brackets_2034.basic_personal_amount > brackets_2024.basic_personal_amount
    end

    test 'all_province_data returns a hash keyed by province code' do
      data = ProvincialBrackets.new(province: nil, year: 2024).all_province_data
      assert_includes data.keys, 'ON'
      assert_includes data.keys, 'AB'
      assert_equal 13, data.keys.length
    end

    test 'all_province_data includes bpa and brackets for each province' do
      data = ProvincialBrackets.new(province: nil, year: 2024).all_province_data
      data.each_value do |province|
        assert province[:bpa].positive?, 'bpa should be positive'
        assert province[:brackets].any?, 'brackets should not be empty'
        province[:brackets].each do |b|
          assert b.key?(:threshold)
          assert b.key?(:rate)
        end
      end
    end

    test 'all_province_data inflates bpa for future years' do
      bpa_2024 = ProvincialBrackets.new(province: nil, year: 2024, inflation_rate: 0.02).all_province_data['ON'][:bpa]
      bpa_2034 = ProvincialBrackets.new(province: nil, year: 2034, inflation_rate: 0.02).all_province_data['ON'][:bpa]
      assert bpa_2034 > bpa_2024
    end

    test 'all_province_data base year returns unmodified thresholds' do
      data = ProvincialBrackets.new(province: nil, year: 2024).all_province_data
      assert_equal 11_865, data['ON'][:bpa]
      assert_equal 0, data['ON'][:brackets].first[:threshold]
    end

    test 'ontario applies no surtax below the first threshold' do
      brackets = Tax::ProvincialBrackets.new(year: 2024, inflation_rate: 0.0, province: 'ON')
      # Basic tax on $50,000 is well under $5,554, so tax equals basic tax.
      assert_equal brackets.basic_tax_on(50_000), brackets.tax_on(50_000)
    end

    test 'ontario applies the 20 percent surtax above the first threshold' do
      brackets = Tax::ProvincialBrackets.new(year: 2024, inflation_rate: 0.0, province: 'ON')
      basic = brackets.basic_tax_on(100_000)
      expected = basic + ((basic - 5_554) * 0.20).round
      assert_operator basic, :>, 5_554
      assert_operator basic, :<, 7_108
      assert_equal expected, brackets.tax_on(100_000)
    end

    test 'ontario applies both surtax tiers above the second threshold' do
      brackets = Tax::ProvincialBrackets.new(year: 2024, inflation_rate: 0.0, province: 'ON')
      basic = brackets.basic_tax_on(150_000)
      expected = basic + ((basic - 5_554) * 0.20).round + ((basic - 7_108) * 0.36).round
      assert_operator basic, :>, 7_108
      assert_equal expected, brackets.tax_on(150_000)
    end

    test 'ontario surtax thresholds inflate with the bracket thresholds' do
      brackets = Tax::ProvincialBrackets.new(year: 2029, inflation_rate: 0.02, province: 'ON')
      assert_equal (5_554 * (1.02**5)).round, brackets.surtax_thresholds.first
    end
  end
end
