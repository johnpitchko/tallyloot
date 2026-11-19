# SpendingSmile is a Value Object representing the retirement spending curve.
#
# Research (Kitces/Blanchett) shows retirees spend less over time — declining
# ~30% from retirement to age 80, then rising ~12% to terminal age as healthcare
# costs increase.
#
# The curve is piecewise linear, anchored to the retiree's retirement_age and
# terminal_age, so it adjusts automatically when those values change.
#
# Usage:
#   smile = SpendingSmile.new(retirement_age: 65, terminal_age: 82)
#   smile.multiplier_for_age(75)  # => ~0.80
#
class SpendingSmile
  TROUGH_AGE        = 80
  TROUGH_MULTIPLIER = 0.70
  TERMINAL_MULTIPLIER = (TROUGH_MULTIPLIER * 1.12).round(4) # ~0.784

  def initialize(retirement_age:, terminal_age:, enabled: true)
    @retirement_age = retirement_age
    @terminal_age   = terminal_age
    @enabled        = enabled
  end

  def multiplier_for_age(age)
    return 1.0 unless @enabled

    if age >= @terminal_age
      TERMINAL_MULTIPLIER
    elsif age >= TROUGH_AGE
      uptick_multiplier(age)
    elsif age > @retirement_age && @retirement_age < TROUGH_AGE
      decline_multiplier(age)
    else
      1.0
    end
  end

  private

  # Linear interpolation from 1.0 at retirement_age down to TROUGH_MULTIPLIER at age 80
  def decline_multiplier(age)
    t = (age - @retirement_age).to_f / (TROUGH_AGE - @retirement_age)
    1.0 - (t * (1.0 - TROUGH_MULTIPLIER))
  end

  # Linear interpolation from TROUGH_MULTIPLIER at age 80 up to TERMINAL_MULTIPLIER at terminal_age
  def uptick_multiplier(age)
    t = (age - TROUGH_AGE).to_f / (@terminal_age - TROUGH_AGE)
    TROUGH_MULTIPLIER + (t * (TERMINAL_MULTIPLIER - TROUGH_MULTIPLIER))
  end
end
