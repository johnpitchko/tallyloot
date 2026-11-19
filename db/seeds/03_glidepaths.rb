# First, ensure allocations exist and index them by name
allocations = Allocation.all.index_by(&:name)

raise 'Allocations missing. Make sure allocations are seeded first.' if allocations.empty?

# Define Glidepaths
glidepaths_data = [
  { name: 'Standard Retirement', description: 'De-risks around retirement age, typical for target-date funds.' },
  { name: 'Aggressive Retirement', description: 'Stays riskier longer, de-risks slowly.' },
  { name: 'Conservative Retirement', description: 'Reduces risk earlier for safety-focused investors.' },
  { name: 'Stay Aggressive Forever', description: 'No de-risking. Remains very aggressive at all ages.' },
]

# Create or update Glidepaths
glidepaths = glidepaths_data.to_h do |attrs|
  glidepath = Glidepath.find_or_initialize_by(name: attrs[:name])
  glidepath.update!(description: attrs[:description])
  [attrs[:name], glidepath]
end

# Glidepath Steps — Delete existing and recreate fresh
GlidepathStep.delete_all

# Define GlidepathSteps for each Glidepath
glidepath_steps_data = [
  # Standard Retirement
  { glidepath: 'Standard Retirement', start_age: 25, allocation: 'Very Aggressive' },
  { glidepath: 'Standard Retirement', start_age: 45, allocation: 'Aggressive' },
  { glidepath: 'Standard Retirement', start_age: 65, allocation: 'Balanced' },
  { glidepath: 'Standard Retirement', start_age: 75, allocation: 'Conservative' },
  { glidepath: 'Standard Retirement', start_age: 85, allocation: 'Very Conservative' },

  # Aggressive Retirement
  { glidepath: 'Aggressive Retirement', start_age: 25, allocation: 'Very Aggressive' },
  { glidepath: 'Aggressive Retirement', start_age: 55, allocation: 'Aggressive' },
  { glidepath: 'Aggressive Retirement', start_age: 70, allocation: 'Growth' },
  { glidepath: 'Aggressive Retirement', start_age: 80, allocation: 'Balanced' },

  # Conservative Retirement
  { glidepath: 'Conservative Retirement', start_age: 25, allocation: 'Growth' },
  { glidepath: 'Conservative Retirement', start_age: 50, allocation: 'Balanced' },
  { glidepath: 'Conservative Retirement', start_age: 65, allocation: 'Conservative' },
  { glidepath: 'Conservative Retirement', start_age: 75, allocation: 'Very Conservative' },

  # Stay Aggressive Forever (dummy step to never change)
  { glidepath: 'Stay Aggressive Forever', start_age: 25, allocation: 'Very Aggressive' },
  { glidepath: 'Stay Aggressive Forever', start_age: 120, allocation: 'Very Aggressive' },
]

# Create GlidepathSteps
glidepath_steps_data.each do |step|
  GlidepathStep.create!(
    glidepath: glidepaths.fetch(step[:glidepath]),
    start_age: step[:start_age],
    allocation: allocations.fetch(step[:allocation])
  )
end
