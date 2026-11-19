allocations_data = [
  {
    name: 'Very Aggressive',
    equity_pct: 1.0,
    fixed_income_pct: 0.0,
    avg_nominal_return: 0.0675,
    description: '100% equities. Maximum growth, maximum risk.',
  },
  {
    name: 'Aggressive',
    equity_pct: 0.85,
    fixed_income_pct: 0.15,
    avg_nominal_return: 0.0625,
    description: '85/15 portfolio. High growth with a small fixed income buffer.',
  },
  {
    name: 'Growth',
    equity_pct: 0.7,
    fixed_income_pct: 0.3,
    avg_nominal_return: 0.06,
    description: '70/30 portfolio. Growth-focused with some risk reduction.',
  },
  {
    name: 'Balanced',
    equity_pct: 0.6,
    fixed_income_pct: 0.4,
    avg_nominal_return: 0.055,
    description: '60/40 portfolio. Balanced between growth and stability.',
  },
  {
    name: 'Conservative',
    equity_pct: 0.4,
    fixed_income_pct: 0.6,
    avg_nominal_return: 0.05,
    description: '40/60 portfolio. Lower risk, income-focused.',
  },
  {
    name: 'Very Conservative',
    equity_pct: 0.0,
    fixed_income_pct: 1.0,
    avg_nominal_return: 0.045,
    description: '100% fixed income. Very low risk, minimal growth.',
  },
]

allocations_data.each do |attrs|
  allocation = Allocation.find_or_initialize_by(name: attrs[:name])
  allocation.update!(
    equity_pct: attrs[:equity_pct],
    fixed_income_pct: attrs[:fixed_income_pct],
    avg_nominal_return: attrs[:avg_nominal_return],
    description: attrs[:description]
  )
end
