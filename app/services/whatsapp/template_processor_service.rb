class Whatsapp::TemplateProcessorService
  pattr_initialize [:channel!, :template_params, :message]

  def call
    return [nil, nil, nil, nil] if template_params.blank?

    process_template_with_params
  end

  private

  def process_template_with_params
    [
      template_params['name'],
      template_params['namespace'],
      template_params['language'],
      processed_templates_params
    ]
  end

  def find_template
    channel.message_templates.find do |t|
      t['name'] == template_params['name'] &&
        t['language']&.downcase == template_params['language']&.downcase &&
        t['status']&.downcase == 'approved'
    end
  end

  def processed_templates_params
    template = find_template
    return if template.blank?

    # Convert legacy format to enhanced format before processing
    converter = Whatsapp::TemplateParameterConverterService.new(template_params, template)
    normalized_params = converter.normalize_to_enhanced

    process_enhanced_template_params(template, normalized_params['processed_params'])
  end

  def process_enhanced_template_params(template, processed_params = nil)
    processed_params ||= template_params['processed_params']
    components = []

    components.concat(process_header_components(processed_params, template))
    components.concat(process_body_components(processed_params, template))
    components.concat(process_footer_components(processed_params))
    components.concat(process_button_components(processed_params))

    @template_params = components
  end

  def process_header_components(processed_params, template = nil)
    return [] if processed_params['header'].blank?

    header_params = build_header_params(processed_params['header'], template)
    header_params.present? ? [{ type: 'header', parameters: header_params }] : []
  end

  def build_header_params(header_data, template = nil)
    parameter_format = template&.dig('parameter_format')
    header_params = []
    header_data.each do |key, value|
      next if value.blank?

      if media_url_with_type?(key, header_data)
        media_name  = header_data['media_name']
        media_type  = header_data['media_type']
        media_param = nil

        if our_storage_url?(value) && cloud_provider?
          media_id = upload_media_to_meta(value, media_type)
          media_param = parameter_builder.build_media_id_parameter(media_id, media_type, media_name) if media_id
        end

        media_param ||= parameter_builder.build_media_parameter(value, media_type, media_name)
        header_params << media_param if media_param
      elsif key != 'media_type' && key != 'media_name' && key != 'media_blob_id'
        if parameter_format == 'NAMED'
          header_params << parameter_builder.build_named_parameter(key, value)
        else
          header_params << parameter_builder.build_parameter(value)
        end
      end
    end
    header_params
  end

  def media_url_with_type?(key, header_data)
    key == 'media_url' && header_data['media_type'].present?
  end

  def our_storage_url?(url)
    url.include?('/rails/active_storage/')
  end

  def cloud_provider?
    channel.provider == 'whatsapp_cloud'
  end

  def upload_media_to_meta(url, media_type)
    Whatsapp::MediaUploadService.new(channel).upload(url, media_type)
  rescue ArgumentError => e
    raise e
  rescue StandardError => e
    Rails.logger.error "WhatsApp media pre-upload failed: #{e.message}"
    nil
  end

  def process_body_components(processed_params, template)
    return [] if processed_params['body'].blank?

    body_params = processed_params['body'].filter_map do |key, value|
      next if value.blank?

      parameter_format = template['parameter_format']
      if parameter_format == 'NAMED'
        parameter_builder.build_named_parameter(key, value)
      else
        parameter_builder.build_parameter(value)
      end
    end

    body_params.present? ? [{ type: 'body', parameters: body_params }] : []
  end

  def process_footer_components(processed_params)
    return [] if processed_params['footer'].blank?

    footer_params = processed_params['footer'].filter_map do |_, value|
      next if value.blank?

      parameter_builder.build_parameter(value)
    end

    footer_params.present? ? [{ type: 'footer', parameters: footer_params }] : []
  end

  def process_button_components(processed_params)
    return [] if processed_params['buttons'].blank?

    button_params = processed_params['buttons'].filter_map.with_index do |button, index|
      next if button.blank?

      if button['type'] == 'url' || button['parameter'].present?
        {
          type: 'button',
          sub_type: button['type'] || 'url',
          index: index,
          parameters: [parameter_builder.build_button_parameter(button)]
        }
      end
    end

    button_params.compact
  end

  def parameter_builder
    @parameter_builder ||= Whatsapp::PopulateTemplateParametersService.new
  end
end
