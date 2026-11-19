# rubocop:disable Metrics/ModuleLength
module FormHelper
  # Generates a Bulma-styled form field with optional label and error messages.
  # If a label is provided, use it; otherwise, humanize the field name.
  def bulma_field(form, field, type: :text_field, show_label: false, **options)
    bulma_field_wrapper(form, field, show_label: show_label) do
      form.public_send(type, field, class: bulma_input_classes(form, field, options), **options)
    end
  end

  # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
  def bulma_collection_select(form, field, collection:, value_method:, text_method:, show_label: false,
                              include_blank: false, **options)
    bulma_field_wrapper(form, field, show_label: show_label) do
      tag.div(class: 'select is-fullwidth') do
        form.collection_select(
          field,
          collection,
          value_method,
          text_method,
          { include_blank: },
          { class: bulma_input_classes(form, field, options) }
        )
      end
    end
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

  # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
  def bulma_grouped_collection_select(form, field, collection:, group_method:, group_label_method:, value_method:,
                                      text_method:, show_label: false, include_blank: false, **options)
    bulma_field_wrapper(form, field, show_label: show_label) do
      tag.div(class: 'select is-fullwidth') do
        form.grouped_collection_select(
          field,
          collection,
          group_method,
          group_label_method,
          value_method,
          text_method,
          { include_blank: },
          { class: bulma_input_classes(form, field, options) }
        )
      end
    end
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

  # Generates a currency text field with a leading $ addon button.
  # Automatically wires currency-input Stimulus controller; caller may pass
  # additional data attrs (e.g. action: "input->foo#bar") which are merged in.
  # Works with both model-backed and plain URL forms (form.object may be nil).
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def bulma_currency_field(form, field, show_label: false, label: nil, **options)
    errors    = form.object&.errors
    has_error = errors ? errors[field].any? : false
    input_classes = ['input', ('is-danger' if has_error)].compact

    extra_data   = options.delete(:data) || {}
    extra_action = extra_data.delete(:action)
    data = {
      controller: 'currency-input',
      action: ['focus->currency-input#focus blur->currency-input#blur', extra_action].compact.join(' '),
      **extra_data,
    }

    tag.div(class: 'field') do
      safe_join([
        (form.label(field, label, class: 'label') if show_label),
        tag.div(class: 'field has-addons') do
          safe_join([
                      tag.div(class: 'control') { tag.span('$', class: 'button is-static') },
                      tag.div(class: 'control is-expanded') do
                        form.text_field(field, class: input_classes.join(' '), inputmode: 'numeric', data:, **options)
                      end,
                    ])
        end,
        (tag.p(errors&.dig(field)&.to_sentence, class: 'help is-danger') if has_error),
      ].compact)
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Generates a Bulma field with a trailing static addon button (e.g., a calculated year badge).
  # Used for date/age fields where a computed value is shown alongside the input.
  #
  # Example:
  #   bulma_field_with_addon(form, :birth_date, addon_target: "currentAge",
  #     data: { year_calculator_target: "birthDate", action: "change->year-calculator#calculate" })
  #
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
  def bulma_field_with_addon(form, field, addon_target:, type: :text_field, addon_text: '--', **options)
    has_error = form.object.errors[field].any?
    input_classes = ['input']
    input_classes << 'is-danger' if has_error

    data_attrs = options.delete(:data) || {}

    tag.div(class: 'field') do
      safe_join([
        form.label(field, class: 'label'),
        tag.div(class: 'field has-addons') do
          safe_join([
                      tag.div(class: 'control is-expanded') do
                        form.public_send(type, field, class: input_classes.join(' '), data: data_attrs, **options)
                      end,
                      tag.div(class: 'control') do
                        tag.span(addon_text, class: 'button is-static year-badge',
                                             data: { year_calculator_target: addon_target })
                      end,
                    ])
        end,
        (tag.p(form.object.errors[field].to_sentence, class: 'help is-danger') if has_error),
      ].compact)
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists

  private

  # rubocop:disable Metrics/AbcSize
  def bulma_field_wrapper(form, field, show_label:, &)
    form_label = form.label(field, class: 'label') if show_label
    has_error = form.object.errors[field].any?

    tag.div(class: 'field') do
      safe_join([
        form_label,
        tag.div(class: 'control', &),
        (tag.p(form.object.errors[field].to_sentence, class: 'help is-danger') if has_error),
      ].compact)
    end
  end
  # rubocop:enable Metrics/AbcSize

  def bulma_input_classes(form, field, options)
    classes = ['input']
    classes << 'is-danger' if form.object.errors[field].any?
    classes += options.delete(:class).to_s.split if options[:class]
    classes.join(' ')
  end
end
# rubocop:enable Metrics/ModuleLength
