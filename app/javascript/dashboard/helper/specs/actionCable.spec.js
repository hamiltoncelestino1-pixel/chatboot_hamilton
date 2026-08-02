import { describe, it, beforeEach, expect, vi } from 'vitest';
import ActionCableConnector from '../actionCable';

vi.mock('shared/helpers/mitt', () => ({
  emitter: {
    emit: vi.fn(),
  },
}));

vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({
    isImpersonating: { value: false },
  }),
}));

global.chatwootConfig = {
  websocketURL: 'wss://test.chatwoot.com',
};

describe('ActionCableConnector - Copilot Tests', () => {
  let store;
  let actionCable;
  let mockDispatch;

  beforeEach(() => {
    vi.clearAllMocks();
    mockDispatch = vi.fn();
    store = {
      $store: {
        dispatch: mockDispatch,
        getters: {
          getCurrentAccountId: 1,
        },
      },
    };

    actionCable = ActionCableConnector.init(store.$store, 'test-token');
  });
  describe('copilot event handlers', () => {
    it('should register the copilot.message.created event handler', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'copilot.message.created'
      );
      expect(actionCable.events['copilot.message.created']).toBe(
        actionCable.onCopilotMessageCreated
      );
    });

    it('should handle the copilot.message.created event through the ActionCable system', () => {
      const copilotData = {
        id: 2,
        content: 'This is a copilot message from ActionCable',
        conversation_id: 456,
        created_at: '2025-05-27T15:58:04-06:00',
        account_id: 1,
      };
      actionCable.onReceived({
        event: 'copilot.message.created',
        data: copilotData,
      });
      expect(mockDispatch).toHaveBeenCalledWith(
        'copilotMessages/upsert',
        copilotData
      );
    });
  });

  describe('pipeline_item event handlers', () => {
    it('should register the pipeline_item.created and pipeline_item.updated event handlers', () => {
      expect(Object.keys(actionCable.events)).toContain(
        'pipeline_item.created'
      );
      expect(Object.keys(actionCable.events)).toContain(
        'pipeline_item.updated'
      );
      expect(actionCable.events['pipeline_item.created']).toBe(
        actionCable.onPipelineItemChanged
      );
      expect(actionCable.events['pipeline_item.updated']).toBe(
        actionCable.onPipelineItemChanged
      );
    });

    it('should dispatch kanban/applyRealtimePipelineItem when a pipeline_item event is received', () => {
      const pipelineItemData = {
        id: 5,
        pipeline_id: 1,
        pipeline_stage_id: 3,
        account_id: 1,
      };
      actionCable.onReceived({
        event: 'pipeline_item.created',
        data: pipelineItemData,
      });
      expect(mockDispatch).toHaveBeenCalledWith(
        'kanban/applyRealtimePipelineItem',
        pipelineItemData
      );
    });
  });
});
