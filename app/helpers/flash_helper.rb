module FlashHelper
  # Generates a Bulma-styled flash notification.
  # type can be :notice, :alert, :info, :success, :danger, etc.
  # dismissible: whether to include the close button
  def bulma_flash(message, type: :notice, dismissible: true, **options)
    return if message.blank?

    classes = flash_classes(type, options)

    tag.div(class: classes, data: { controller: 'flash', flash_type_value: type }, **options) do
      safe_join([
        (tag.button('', class: 'delete', data: { action: 'click->flash#dismiss' }) if dismissible),
        message,
      ].compact)
    end
  end

  private

  def flash_classes(type, options)
    bulma_class = flash_type_to_bulma_class(type)
    classes = ['notification', bulma_class]
    classes.concat(Array(options.delete(:class)))
    classes.join(' ')
  end

  def flash_type_to_bulma_class(type)
    case type.to_sym
    when :notice, :success then 'is-success'
    when :alert, :error then 'is-danger'
    when :info then 'is-info'
    else ''
    end
  end
end
