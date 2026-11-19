class Crossover
  attr_reader :year, :amount, :series

  def self.for_household(periods)
    new(periods)
  end

  def self.for_user(periods, user)
    new(periods, account_ids: Set.new(user.account_ids))
  end

  def reached?
    @year.present?
  end

  def to_h(user_id: 'all', user_name: nil)
    {
      user_id:,
      user_name:,
      years: series.pluck(:year),
      contributions: series.pluck(:contributions),
      growth: series.pluck(:growth),
      crossover_year: year,
      crossover_amount: amount,
    }
  end

  private

  def initialize(periods, account_ids: nil)
    @series = periods.map do |period|
      contributions, growth = account_series(period, account_ids)
      { year: period.year, contributions:, growth: }
    end
    detect_crossover
  end

  def account_series(period, account_ids)
    if account_ids
      aps = period.account_periods.select { |ap| account_ids.include?(ap.account_id) }
      [aps.sum(&:contribution_amount), aps.sum(&:growth)]
    else
      [period.contribution_amount, period.growth]
    end
  end

  def detect_crossover
    entry = @series.find { |e| e[:contributions].positive? && e[:growth] >= e[:contributions] }
    return unless entry

    @year = entry[:year]
    @amount = entry[:growth]
  end
end
