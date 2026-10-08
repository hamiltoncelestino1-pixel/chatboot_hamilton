import { nextTick, ref } from 'vue';

/**
 * Promise-based prompt used by store/modules/kanban/actions.js#moveItem to ask for a lost
 * reason mid-move, without coupling the Vuex action to a specific component.
 * LostReasonModal.vue (mounted once in KanbanIndex.vue) is the only consumer that renders
 * based on `isOpen` and calls confirm/cancel/cancelAllPendingPrompts.
 *
 * State is module-scoped (shared across every moveItem call), so a queue of pending
 * resolvers is kept instead of a single one: this survives two moveItem calls landing
 * before either is answered (the second no longer silently overwrites the first's resolver,
 * orphaning that Promise forever) and lets the modal drain every pending prompt at once via
 * cancelAllPendingPrompts when it unmounts mid-prompt (e.g. user navigates away).
 */
const isOpen = ref(false);
const queue = [];

export function useLostReasonPrompt() {
  const promptForLostReason = () =>
    new Promise(resolve => {
      queue.push(resolve);
      isOpen.value = true;
    });

  // Closes then reopens (next tick) when another prompt is queued, instead of just moving
  // to the next resolver - LostReasonModal's watch(isOpen) only resets its selected reason
  // on a false->true transition, so this is what makes the next prompt start clean.
  const settleCurrent = reasonId => {
    const resolve = queue.shift();
    isOpen.value = false;
    resolve?.(reasonId);
    if (queue.length) {
      nextTick(() => {
        isOpen.value = true;
      });
    }
  };

  const confirmLostReason = reasonId => settleCurrent(reasonId);
  const cancelLostReason = () => settleCurrent(null);

  const cancelAllPendingPrompts = () => {
    isOpen.value = false;
    while (queue.length) {
      queue.shift()?.(null);
    }
  };

  return {
    isOpen,
    promptForLostReason,
    confirmLostReason,
    cancelLostReason,
    cancelAllPendingPrompts,
  };
}
