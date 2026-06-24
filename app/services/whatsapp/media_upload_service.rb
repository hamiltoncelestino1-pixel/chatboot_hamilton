class Whatsapp::MediaUploadService
  SUPPORTED_MIME_TYPES = {
    'image'    => %w[image/jpeg image/png],
    'video'    => %w[video/mp4 video/3gpp],
    'document' => %w[application/pdf]
  }.freeze

  def initialize(whatsapp_channel)
    @channel = whatsapp_channel
  end

  def upload(file_url, media_type)
    validate_media_type!(media_type)

    file_bytes = download_file(file_url)
    mime_type  = detect_mime_type(file_bytes, file_url, media_type)

    validate_mime_type!(mime_type, media_type)

    response = HTTParty.post(
      "#{phone_id_path}/media",
      headers: { 'Authorization' => "Bearer #{api_key}" },
      body: {
        messaging_product: 'whatsapp',
        type: mime_type,
        file: file_bytes
      }
    )

    raise "Meta media upload failed (#{response.code}): #{response.body}" unless response.success?

    response.parsed_response['id']
  end

  private

  def download_file(url)
    response = HTTParty.get(url, follow_redirects: true)
    raise "Failed to download file from storage (#{response.code})" unless response.success?

    response.body
  end

  def detect_mime_type(bytes, url, media_type)
    filename = File.basename(URI.parse(url).path)
    Marcel::MimeType.for(StringIO.new(bytes), name: filename)
  rescue StandardError
    SUPPORTED_MIME_TYPES[media_type]&.first
  end

  def validate_media_type!(media_type)
    return if SUPPORTED_MIME_TYPES.key?(media_type)

    raise ArgumentError, "Tipo de mídia '#{media_type}' não é suportado pelo WhatsApp para templates"
  end

  def validate_mime_type!(mime_type, media_type)
    allowed = SUPPORTED_MIME_TYPES[media_type] || []
    return if allowed.include?(mime_type)

    raise ArgumentError,
          "Formato de arquivo não suportado pelo WhatsApp para templates do tipo '#{media_type}'. " \
          "Formatos aceitos: #{allowed.join(', ')}"
  end

  def phone_id_path
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/v18.0/#{@channel.provider_config['phone_number_id']}"
  end

  def api_key
    @channel.provider_config['api_key']
  end
end