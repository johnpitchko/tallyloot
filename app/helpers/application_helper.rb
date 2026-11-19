module ApplicationHelper
  def number_to_percent(decimal, **options)
    return '0%' if decimal.nil? || decimal.zero?

    number_to_percentage(decimal * 100, options)
  end
end
