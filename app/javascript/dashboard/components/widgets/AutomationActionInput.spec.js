import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import AutomationActionInput from './AutomationActionInput.vue';
import AutomationActionPipelineLabelInput from './AutomationActionPipelineLabelInput.vue';

describe('AutomationActionInput.vue', () => {
  let store;

  const actionTypes = [
    {
      key: 'add_pipeline_item_label',
      label: 'Add label',
      inputType: 'pipeline_label_select',
    },
    {
      key: 'remove_pipeline_item_label',
      label: 'Remove label',
      inputType: 'pipeline_label_select',
    },
  ];

  const mountComponent = modelValue =>
    shallowMount(AutomationActionInput, {
      props: { modelValue, actionTypes },
      global: {
        plugins: [store],
        mocks: { $t: msg => msg },
        stubs: { AutomationActionPipelineLabelInput: false },
      },
    });

  beforeEach(() => {
    store = createStore({
      getters: {
        'kanban/getPipelines': () => [],
        'labels/getPipelineLabels': () => [{ title: 'quente' }],
      },
    });
    vi.spyOn(store, 'dispatch').mockResolvedValue();
  });

  // Regression test for task 15: move_pipeline_item_stage/export_pipeline_item,
  // assign_pipeline_item_agent/assign_pipeline_item_team and add_pipeline_item_label/
  // remove_pipeline_item_label pairs share the same inputType, so without a :key tied to
  // action_name, Vue reuses the same child instance across the swap and its mounted()-only
  // internal state never resyncs with the (now reset) modelValue.
  it('resyncs the pipeline label child state when action_name changes within the same inputType', async () => {
    const wrapper = mountComponent({
      action_name: 'add_pipeline_item_label',
      action_params: { pipeline_id: 1, labels: ['quente'] },
    });

    const childBefore = wrapper.findComponent(
      AutomationActionPipelineLabelInput
    );
    expect(childBefore.vm.selectedLabels).toEqual([
      { id: 'quente', name: 'quente' },
    ]);

    // Mirrors useAutomation#resetAction: action_name changes and action_params is cleared.
    await wrapper.setProps({
      modelValue: {
        action_name: 'remove_pipeline_item_label',
        action_params: [],
      },
    });

    const childAfter = wrapper.findComponent(
      AutomationActionPipelineLabelInput
    );
    expect(childAfter.vm.pipelineId).toBeNull();
    expect(childAfter.vm.selectedLabels).toEqual([]);
  });
});
