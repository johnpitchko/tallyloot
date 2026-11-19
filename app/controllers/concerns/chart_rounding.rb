# Rounds dollar amounts to the nearest $1,000 for chart display.
#
# Projected income series are computed in whole dollars, and the nominal→real
# round trip (inflate → fill withdrawals → deflate) leaves ±$1 rounding jitter.
# On a near-flat series (e.g. income exactly meeting the goal) the y-axis
# auto-scales to that tiny spread, magnifying the jitter into a spurious wobble.
# Rounding every plotted value to the nearest $1,000 collapses that noise so
# series that meet coincide exactly, without visibly altering values that are
# already in the hundreds of thousands.
module ChartRounding
  module_function

  def round_to_nearest_thousand(amount)
    return amount if amount.nil?

    (amount / 1000.0).round * 1000
  end

  def round_series(values)
    values.map { |v| round_to_nearest_thousand(v) }
  end
end
