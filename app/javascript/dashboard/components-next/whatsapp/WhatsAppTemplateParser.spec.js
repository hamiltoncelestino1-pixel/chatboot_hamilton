import { mount, flushPromises } from '@vue/test-utils';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import WhatsAppTemplateParser from './WhatsAppTemplateParser.vue';

vi.mock('dashboard/helper/uploadHelper', () => ({
  uploadFile: vi.fn(),
}));

const documentTemplate = {
  name: 'invoice',
  language: 'en',
  category: 'UTILITY',
  components: [
    { type: 'HEADER', format: 'DOCUMENT' },
    { type: 'BODY', text: 'Hello there' },
  ],
};

const escapedBodyTemplate = {
  name: 'delivery_confirmation',
  language: 'en',
  category: 'UTILITY',
  components: [
    {
      type: 'BODY',
      text: 'Hi {{1}},\\nYour order {{2}} shipped.\\n\\nThanks!',
    },
  ],
};

const plainBodyTemplate = {
  name: 'greet',
  language: 'en',
  category: 'UTILITY',
  components: [{ type: 'BODY', text: 'Hello {{1}}!' }],
};

const createWrapper = (template = documentTemplate) =>
  mount(WhatsAppTemplateParser, {
    props: { template },
    global: { stubs: { Input: true } },
  });

describe('WhatsAppTemplateParser', () => {
  describe('handleMediaUpload', () => {
    it('keeps the uploaded blob id and url so the backend can attach the document', async () => {
      uploadFile.mockResolvedValue({
        fileUrl: 'http://storage/sample.pdf',
        blobId: 'blob-123',
      });
      const wrapper = createWrapper();

      const fileInput = wrapper.find('input[type="file"]');
      const file = new File(['pdf-bytes'], 'sample.pdf', {
        type: 'application/pdf',
      });
      Object.defineProperty(fileInput.element, 'files', {
        value: [file],
        configurable: true,
      });
      await fileInput.trigger('change');
      await flushPromises();

      const { header } = wrapper.vm.processedParams;
      expect(header.media_url).toBe('http://storage/sample.pdf');
      expect(header.media_blob_id).toBe('blob-123');
      expect(header.media_name).toBe('sample.pdf');
    });
  });

  describe('updateMediaUrl', () => {
    it('clears a stale blob id when the URL is typed manually', () => {
      const wrapper = createWrapper();
      wrapper.vm.processedParams.header.media_blob_id = 'blob-123';

      wrapper.vm.updateMediaUrl('https://example.com/manual.pdf');

      expect(wrapper.vm.processedParams.header.media_url).toBe(
        'https://example.com/manual.pdf'
      );
      expect(wrapper.vm.processedParams.header.media_blob_id).toBeUndefined();
    });
  });

  describe('sendMessage', () => {
    it('includes the media blob id in the emitted template payload', async () => {
      const wrapper = createWrapper();
      wrapper.vm.processedParams.header.media_url = 'http://storage/sample.pdf';
      wrapper.vm.processedParams.header.media_blob_id = 'blob-123';

      wrapper.vm.sendMessage();
      await flushPromises();

      const payload = wrapper.emitted('sendMessage')[0][0];
      expect(payload.templateParams.processed_params.header.media_blob_id).toBe(
        'blob-123'
      );
    });

    it('emits the rendered message with real line breaks', async () => {
      const wrapper = createWrapper(escapedBodyTemplate);
      await flushPromises();
      wrapper.vm.processedParams.body['1'] = 'John';
      wrapper.vm.processedParams.body['2'] = 'A-123';
      await flushPromises();

      wrapper.vm.sendMessage();
      await flushPromises();

      const payload = wrapper.emitted('sendMessage')[0][0];
      expect(payload.message).toBe(
        'Hi John,\nYour order A-123 shipped.\n\nThanks!'
      );
    });
  });

  describe('renderedTemplate', () => {
    it('converts escaped newlines in the body into real line breaks', async () => {
      const wrapper = createWrapper(escapedBodyTemplate);
      await flushPromises();
      wrapper.vm.processedParams.body['1'] = 'John';
      wrapper.vm.processedParams.body['2'] = 'A-123';
      await flushPromises();

      expect(wrapper.vm.renderedTemplate).toBe(
        'Hi John,\nYour order A-123 shipped.\n\nThanks!'
      );
    });

    it('leaves a body without escape sequences unchanged', async () => {
      const wrapper = createWrapper(plainBodyTemplate);
      await flushPromises();
      wrapper.vm.processedParams.body['1'] = 'Sam';
      await flushPromises();

      expect(wrapper.vm.renderedTemplate).toBe('Hello Sam!');
    });
  });
});
