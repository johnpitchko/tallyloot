module Tax
  # Calculates Canadian provincial/territorial income tax using 2024 bracket rates.
  # Thresholds and basic personal amounts are inflated forward from 2024 using the
  # portfolio inflation rate to approximate future-year brackets.
  #
  # Returns 0 for nil or unrecognised provinces so the rest of the tax estimate
  # degrades gracefully when a household has not set a province.
  #
  # rubocop:disable Metrics/ClassLength
  class ProvincialBrackets
    BASE_YEAR = 2024

    ON_SURTAX_TIERS = [
      { threshold: 5_554, rate: 0.20 },
      { threshold: 7_108, rate: 0.36 },
    ].freeze

    PROVINCE_DATA = {
      'AB' => {
        basic_personal_amount: 21_003,
        brackets: [
          { threshold: 0,       rate: 0.10 },
          { threshold: 148_269, rate: 0.12 },
          { threshold: 177_922, rate: 0.13 },
          { threshold: 237_230, rate: 0.14 },
          { threshold: 355_845, rate: 0.15 },
        ],
      },
      'BC' => {
        basic_personal_amount: 11_981,
        brackets: [
          { threshold: 0,       rate: 0.0506 },
          { threshold: 45_654,  rate: 0.077 },
          { threshold: 91_310,  rate: 0.105 },
          { threshold: 104_835, rate: 0.1229 },
          { threshold: 127_299, rate: 0.147 },
          { threshold: 172_602, rate: 0.168 },
          { threshold: 240_716, rate: 0.205 },
        ],
      },
      'MB' => {
        basic_personal_amount: 15_780,
        brackets: [
          { threshold: 0,      rate: 0.108 },
          { threshold: 36_842, rate: 0.1275 },
          { threshold: 79_625, rate: 0.174 },
        ],
      },
      'NB' => {
        basic_personal_amount: 12_458,
        brackets: [
          { threshold: 0,       rate: 0.094 },
          { threshold: 47_715,  rate: 0.1482 },
          { threshold: 95_431,  rate: 0.1652 },
          { threshold: 176_756, rate: 0.195 },
        ],
      },
      'NL' => {
        basic_personal_amount: 10_818,
        brackets: [
          { threshold: 0,       rate: 0.087 },
          { threshold: 43_198,  rate: 0.145 },
          { threshold: 86_395,  rate: 0.158 },
          { threshold: 154_244, rate: 0.178 },
          { threshold: 215_943, rate: 0.198 },
          { threshold: 275_870, rate: 0.208 },
          { threshold: 551_739, rate: 0.213 },
        ],
      },
      'NS' => {
        basic_personal_amount: 8_481,
        brackets: [
          { threshold: 0,       rate: 0.0879 },
          { threshold: 29_590,  rate: 0.1495 },
          { threshold: 59_180,  rate: 0.1667 },
          { threshold: 93_000,  rate: 0.175 },
          { threshold: 150_000, rate: 0.21 },
        ],
      },
      'NT' => {
        basic_personal_amount: 16_593,
        brackets: [
          { threshold: 0,       rate: 0.059 },
          { threshold: 50_597,  rate: 0.086 },
          { threshold: 101_198, rate: 0.122 },
          { threshold: 164_525, rate: 0.1405 },
        ],
      },
      'NU' => {
        basic_personal_amount: 17_925,
        brackets: [
          { threshold: 0,       rate: 0.04 },
          { threshold: 53_268,  rate: 0.07 },
          { threshold: 106_537, rate: 0.09 },
          { threshold: 173_205, rate: 0.115 },
        ],
      },
      'ON' => {
        basic_personal_amount: 11_865,
        brackets: [
          { threshold: 0,       rate: 0.0505 },
          { threshold: 51_446,  rate: 0.0915 },
          { threshold: 102_894, rate: 0.1116 },
          { threshold: 150_000, rate: 0.1216 },
          { threshold: 220_000, rate: 0.1316 },
        ],
      },
      'PE' => {
        basic_personal_amount: 12_000,
        brackets: [
          { threshold: 0,       rate: 0.0965 },
          { threshold: 32_656,  rate: 0.1363 },
          { threshold: 64_313,  rate: 0.1665 },
          { threshold: 105_000, rate: 0.18 },
          { threshold: 140_000, rate: 0.1875 },
        ],
      },
      'QC' => {
        basic_personal_amount: 17_183,
        brackets: [
          { threshold: 0,       rate: 0.14 },
          { threshold: 51_780,  rate: 0.19 },
          { threshold: 103_545, rate: 0.24 },
          { threshold: 126_000, rate: 0.2575 },
        ],
      },
      'SK' => {
        basic_personal_amount: 17_661,
        brackets: [
          { threshold: 0,       rate: 0.105 },
          { threshold: 49_720,  rate: 0.125 },
          { threshold: 142_058, rate: 0.145 },
        ],
      },
      'YT' => {
        basic_personal_amount: 15_705,
        brackets: [
          { threshold: 0,       rate: 0.064 },
          { threshold: 55_867,  rate: 0.09 },
          { threshold: 111_733, rate: 0.109 },
          { threshold: 154_906, rate: 0.128 },
          { threshold: 500_000, rate: 0.15 },
        ],
      },
    }.freeze

    def initialize(province:, year:, inflation_rate: 0.02)
      @province = province
      @year = year
      @inflation_rate = inflation_rate
    end

    def tax_on(gross_income)
      basic = basic_tax_on(gross_income)
      basic + surtax_on(basic)
    end

    def basic_tax_on(gross_income)
      return 0 if gross_income <= 0 || province_data.nil?

      net_income = [gross_income - basic_personal_amount, 0].max
      return 0 if net_income <= 0

      calculate_marginal_tax(net_income)
    end

    def surtax_thresholds
      return [] unless @province == 'ON'

      ON_SURTAX_TIERS.map { |t| (t[:threshold] * inflation_factor).round }
    end

    def basic_personal_amount
      return 0 if province_data.nil?

      (province_data[:basic_personal_amount] * inflation_factor).round
    end

    def brackets
      return [] if province_data.nil?

      province_data[:brackets].map do |b|
        { threshold: (b[:threshold] * inflation_factor).round, rate: b[:rate] }
      end
    end

    def supported?
      province_data.present?
    end

    def all_province_data
      factor = inflation_factor
      PROVINCE_DATA.transform_values do |data|
        {
          bpa: (data[:basic_personal_amount] * factor).round,
          brackets: data[:brackets].map { |b| { threshold: (b[:threshold] * factor).round, rate: b[:rate] } },
        }
      end
    end

    private

    def province_data
      PROVINCE_DATA[@province]
    end

    def inflation_factor
      years_elapsed = [@year - BASE_YEAR, 0].max
      (1 + @inflation_rate)**years_elapsed
    end

    def surtax_on(basic)
      return 0 unless @province == 'ON'

      ON_SURTAX_TIERS.sum do |tier|
        threshold = (tier[:threshold] * inflation_factor).round
        excess = basic - threshold
        excess.positive? ? (excess * tier[:rate]).round : 0
      end
    end

    def calculate_marginal_tax(net_income)
      tax = 0.0
      bracket_list = brackets

      bracket_list.each_with_index do |bracket, i|
        lower = bracket[:threshold]
        next if net_income <= lower

        upper = bracket_list[i + 1]&.fetch(:threshold) || Float::INFINITY
        income_in_bracket = [net_income, upper].min - lower
        tax += income_in_bracket * bracket[:rate]
      end

      tax.round
    end
  end
  # rubocop:enable Metrics/ClassLength
end
