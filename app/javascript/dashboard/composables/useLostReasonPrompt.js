import { ref } from 'vue';

/**
 * Singleton promise-based prompt used by store/modules/kanban/actions.js#moveItem to ask
 * for a lost reason mid-move, without coupling the Vuex action to a specific component.
 * LostReasonModal.vue (mounted once in KanbanIndex.vue) is the only consumer that renders
 * based on `isOpen` and calls confirm/cancel.
 */
const isOpen = ref(false);
let resolvePrompt = null;

export function useLostReasonPrompt() {
  const promptForLostReason = () => {
    isOpen.value = true;
    return new Promise(resolve => {
      resolvePrompt = resolve;
    });
  };

  const confirmLostReason = reasonId => {
    isOpen.value = false;
    resolvePrompt?.(reasonId);
    resolvePrompt = null;
  };

  const cancelLostReason = () => {
    isOpen.value = false;
    resolvePrompt?.(null);
    resolvePrompt = null;
  };

  return { isOpen, promptForLostReason, confirmLostReason, cancelLostReason };
}
