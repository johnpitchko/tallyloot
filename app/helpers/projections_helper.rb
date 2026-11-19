module ProjectionsHelper
  # CSS class helpers

  def column_group_class(index)
    index.zero? ? 'group-border' : 'subgroup-border'
  end

  def net_change_td_class(value, border_class: 'group-border')
    "has-text-right #{net_change_color(value)} has-tooltip #{border_class}"
  end

  def income_source_td_class(tooltip, group_border: false)
    classes = ['has-text-right']
    classes << 'group-border' if group_border
    classes << 'has-tooltip' if tooltip.present?
    classes.join(' ')
  end

  def tooltip_data(tooltip)
    return '' if tooltip.blank?

    tag.attributes(data: { tooltip: tooltip })
  end

  # Net change helpers (for +/- column showing total change including growth)

  def net_change_color(value)
    return '' if value.nil? || value.zero?

    value.positive? ? 'has-text-success' : 'has-text-danger'
  end

  def format_net_change(value)
    return '—' if value.nil? || value.zero?

    prefix = value.positive? ? '+' : ''
    "#{prefix}#{number_to_currency(value, precision: 0)}"
  end

  # Tooltip helpers
  #
  # Both type summaries and period summaries share the same interface
  # (contribution_amount, withdrawal_amount, growth, net_change),
  # so a single method handles both.

  def financial_summary_tooltip(summary)
    return '' unless summary

    lines = []
    lines << currency_line('Contributions', summary.contribution_amount)
    lines << currency_line('Withdrawals', summary.withdrawal_amount, prefix: '-')
    lines << "Growth: #{number_to_currency(summary.growth, precision: 0)}"
    lines << "Total: #{format_net_change(summary.net_change)}"
    lines.compact.join("\n")
  end

  def currency_line(label, amount, prefix: '')
    return nil unless amount.positive?

    "#{label}: #{prefix}#{number_to_currency(amount, precision: 0)}"
  end

  def benefits_tooltip(period)
    period.benefit_periods.select { |b| b.income_amount.positive? }.map do |b|
      "#{b.name}: #{number_to_currency(b.income_amount, precision: 0)}"
    end.join("\n")
  end

  def pensions_tooltip(period)
    period.pension_periods.select { |p| p.income_amount.positive? }.map do |p|
      "#{p.name}: #{number_to_currency(p.income_amount, precision: 0)}"
    end.join("\n")
  end

  def employment_tooltip(period)
    period.employment_periods.select { |e| e.income_amount.positive? }.map do |e|
      "#{e.name}: #{number_to_currency(e.income_amount, precision: 0)}"
    end.join("\n")
  end

  def withdrawals_tooltip(period)
    period.account_periods.select { |a| a.withdrawal_amount.positive? }.map do |a|
      "#{a.account.name}: #{number_to_currency(a.withdrawal_amount, precision: 0)}"
    end.join("\n")
  end

  def tax_tooltip(period)
    tax = period.tax_estimate
    return '' if tax.estimated_tax.zero?

    lines = []
    lines << "Federal: #{number_to_currency(tax.federal_tax, precision: 0)}"
    lines << "Provincial: #{number_to_currency(tax.provincial_tax, precision: 0)}" if tax.provincial_tax.positive?
    lines << "Effective rate: #{number_to_percentage(tax.effective_rate * 100, precision: 1)}"
    lines.join("\n")
  end
end
