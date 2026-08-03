import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

/**
 * Shared pipeline-selection logic reused by the pipeline automation action inputs
 * (AutomationActionCreatePipelineItemInput, AutomationActionPipelineStageInput,
 * AutomationActionPipelineAssigneeInput, AutomationActionPipelineLabelInput,
 * AutomationActionPipelineUpdateFieldsInput): fetch-on-mount, options list, and
 * autoselecting the first pipeline once the list loads if nothing is selected yet.
 *
 * The autoselect callback is set via `onAutoSelect(callback)` instead of a constructor
 * argument so callers can declare it after destructuring `pipelineId` (avoids a
 * use-before-define on `pipelineId` inside the callback body). It fires only when
 * defaultToFirstPipeline actually picks a pipeline (on mount or once the async fetch
 * resolves) - not on every pipelineId write - so callers can hook their own side effects
 * (e.g. re-emitting the payload, defaulting a first stage) exactly where the original
 * per-component implementations did.
 */
export function usePipelineSelector(initialPipelineId = null) {
  const store = useStore();
  const pipelines = useMapGetter('kanban/getPipelines');

  const pipelineId = ref(initialPipelineId);
  let autoSelectCallback = () => {};

  const pipelineOptions = computed(() =>
    pipelines.value.map(pipeline => ({ id: pipeline.id, name: pipeline.name }))
  );

  const selectedPipelineOption = computed(
    () =>
      pipelineOptions.value.find(option => option.id === pipelineId.value) ||
      null
  );

  const defaultToFirstPipeline = () => {
    if (!pipelineOptions.value.length) return;
    pipelineId.value = pipelineOptions.value[0].id;
    autoSelectCallback();
  };

  const onAutoSelect = callback => {
    autoSelectCallback = callback;
  };

  onMounted(() => {
    if (!pipelines.value.length) {
      store.dispatch('kanban/fetchPipelines');
    }
  });

  watch(pipelines, list => {
    if (!pipelineId.value && list.length) {
      defaultToFirstPipeline();
    }
  });

  return {
    pipelineId,
    pipelineOptions,
    selectedPipelineOption,
    defaultToFirstPipeline,
    onAutoSelect,
  };
}
