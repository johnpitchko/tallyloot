module ProjectionHelper
  def tab_item(name, path)
    tag.li class: active_class(path) do
      link_to name, path
    end
  end

  def active_class(path)
    'is-active' if current_page?(path)
  end

  def icon_for_action(action)
    case action.kind
    when 'contribution'
      'arrow-up-right'
    when 'update'
      'heroicon-o-pencil-square'
    when 'destroy'
      'heroicon-o-trash'
    else
      'heroicon-o-question-mark-circle'
    end
  end

  # Returns border style for the first column of each group (Accounts, Benefits, Pensions)
  # in the projection table to visually separate column groups with a vertical border.
  # Only applies to the first user's first item to create one border at the group's left edge.
  def column_group_border_style(user_idx, item_idx)
    return unless user_idx.zero? && item_idx.zero?

    'border-left: 1px solid #353a46;'
  end
end
