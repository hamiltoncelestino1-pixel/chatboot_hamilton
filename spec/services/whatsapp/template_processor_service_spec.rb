require 'rails_helper'

describe Whatsapp::TemplateProcessorService do
  let!(:channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }

  def process(header)
    template_params = {
      'name' => 'sample_shipping_confirmation',
      'namespace' => '23423423_2342423_324234234_2343224',
      'language' => 'en_US',
      'category' => 'SHIPPING_UPDATE',
      'processed_params' => { 'header' => header }
    }
    _name, _namespace, _lang, components = described_class.new(channel: channel, template_params: template_params).call
    components
  end

  def header_component(components)
    components.find { |component| component[:type] == 'header' }
  end

  describe '#call with a media header' do
    it 'does not send media_blob_id as a header text parameter' do
      header = header_component(
        process('media_url' => 'https://example.com/file.pdf', 'media_type' => 'document',
                'media_name' => 'file.pdf', 'media_blob_id' => 'signed-blob-id')
      )

      expect(header).to be_present
      # only the document media parameter, never a text parameter built from media_blob_id/media_name
      expect(header[:parameters].pluck(:type)).to contain_exactly('document')
      expect(header[:parameters]).to(be_none { |param| param[:type] == 'text' })
    end

    it 'still builds the media parameter from media_url' do
      header = header_component(process('media_url' => 'https://example.com/image.jpg', 'media_type' => 'image'))

      expect(header[:parameters].first).to include(type: 'image', image: { link: 'https://example.com/image.jpg' })
    end

    it 'keeps header text variables while ignoring media_blob_id' do
      header = header_component(process('1' => 'Hello', 'media_blob_id' => 'signed-blob-id'))

      expect(header[:parameters].pluck(:text)).to eq(['Hello'])
    end
  end
end
