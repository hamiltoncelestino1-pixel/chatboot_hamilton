import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import assignmentPoliciesAPI from 'dashboard/api/assignmentPolicies';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import CollaboratorsPage from '../CollaboratorsPage.vue';

vi.mock('vue-router');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/assignmentPolicies', () => ({
  default: {
    getInboxPolicy: vi.fn(),
    get: vi.fn(),
    setInboxPolicy: vi.fn(),
    removeInboxPolicy: vi.fn(),
  },
}));

describe('CollaboratorsPage.vue', () => {
  let store;
  let dispatchSpy;

  const inbox = {
    id: 1,
    enable_auto_assignment: true,
    auto_assignment_config: {},
  };

  const mountComponent = () =>
    shallowMount(CollaboratorsPage, {
      props: { inbox },
      global: {
        plugins: [store],
        mocks: { $t: msg => msg },
      },
    });

  // SettingsAccordion/SettingsToggleSection wrap the RadioCards and the restrict-to-online
  // toggle in named/default slots; shallowMount's auto-stubs don't render slot content, so
  // template-wiring tests need these two unstubbed to actually reach the real child components.
  const mountComponentDeep = () =>
    shallowMount(CollaboratorsPage, {
      props: { inbox },
      global: {
        plugins: [store],
        mocks: { $t: msg => msg },
        stubs: { SettingsAccordion: false, SettingsToggleSection: false },
      },
    });

  beforeEach(() => {
    useRoute.mockReturnValue({ params: { accountId: '1' } });
    useRouter.mockReturnValue({ push: vi.fn() });

    assignmentPoliciesAPI.getInboxPolicy.mockRejectedValue(
      new Error('no policy attached')
    );
    assignmentPoliciesAPI.get.mockResolvedValue({ data: [] });

    store = createStore({
      getters: {
        'agents/getAgents': () => [],
        'accounts/isFeatureEnabledonAccount': () => () => true,
        'agentCapacityPolicies/getAgentCapacityPolicies': () => [],
      },
    });
    dispatchSpy = vi
      .spyOn(store, 'dispatch')
      .mockImplementation((action, payload) => {
        if (action === 'inboxMembers/get') {
          return Promise.resolve({ data: { payload: [] } });
        }
        return Promise.resolve(payload);
      });

    useAlert.mockClear();
  });

  it('shows the direct assignment mode UI when assignment_v2 is enabled and no policy is linked', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    expect(wrapper.vm.showDirectAssignmentModeUI).toBe(true);
  });

  it('updates assignment_mode and dispatches updateInbox when a radio option is selected', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.updateAssignmentMode('balanced');

    expect(wrapper.vm.assignmentMode).toBe('balanced');
    expect(dispatchSpy).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: inbox.id,
      formData: false,
      auto_assignment_config: {
        ...inbox.auto_assignment_config,
        assignment_mode: 'balanced',
      },
    });
    expect(useAlert).toHaveBeenCalled();
  });

  it('reverts assignment_mode when updateInbox fails', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    dispatchSpy.mockImplementation(action => {
      if (action === 'inboxes/updateInbox') {
        return Promise.reject(new Error('failed'));
      }
      return Promise.resolve();
    });

    await wrapper.vm.updateAssignmentMode('balanced');

    expect(wrapper.vm.assignmentMode).toBe('round_robin');
    expect(useAlert).toHaveBeenCalled();
  });

  it('updates restrict_to_online_agents and dispatches updateInbox on toggle', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    await wrapper.vm.updateRestrictToOnlineAgents(true);

    expect(wrapper.vm.restrictToOnlineAgents).toBe(true);
    expect(dispatchSpy).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: inbox.id,
      formData: false,
      auto_assignment_config: {
        ...inbox.auto_assignment_config,
        restrict_to_online_agents: true,
      },
    });
  });

  it('reverts restrict_to_online_agents when updateInbox fails', async () => {
    const wrapper = mountComponent();
    await flushPromises();

    dispatchSpy.mockImplementation(action => {
      if (action === 'inboxes/updateInbox') {
        return Promise.reject(new Error('failed'));
      }
      return Promise.resolve();
    });

    await wrapper.vm.updateRestrictToOnlineAgents(true);

    expect(wrapper.vm.restrictToOnlineAgents).toBe(false);
    expect(useAlert).toHaveBeenCalled();
  });

  describe('template wiring', () => {
    it('calls updateAssignmentMode with the right payload when a RadioCard emits select', async () => {
      const wrapper = mountComponentDeep();
      await flushPromises();

      const radioCards = wrapper.findAllComponents(RadioCard);
      const balancedCard = radioCards.find(
        card => card.props('id') === 'balanced'
      );
      balancedCard.vm.$emit('select', 'balanced');
      await flushPromises();

      expect(dispatchSpy).toHaveBeenCalledWith('inboxes/updateInbox', {
        id: inbox.id,
        formData: false,
        auto_assignment_config: {
          ...inbox.auto_assignment_config,
          assignment_mode: 'balanced',
        },
      });
    });

    it('calls updateRestrictToOnlineAgents with the right payload when the toggle emits update:model-value', async () => {
      const wrapper = mountComponentDeep();
      await flushPromises();

      const toggles = wrapper.findAllComponents(SettingsToggleSection);
      const restrictToggle = toggles.find(
        toggle =>
          toggle.props('header') ===
          'INBOX_MGMT.ASSIGNMENT.RESTRICT_TO_ONLINE_AGENTS.LABEL'
      );
      restrictToggle.vm.$emit('update:modelValue', true);
      await flushPromises();

      expect(dispatchSpy).toHaveBeenCalledWith('inboxes/updateInbox', {
        id: inbox.id,
        formData: false,
        auto_assignment_config: {
          ...inbox.auto_assignment_config,
          restrict_to_online_agents: true,
        },
      });
    });
  });

  describe('when a policy is already linked', () => {
    it('sets showDirectAssignmentModeUI to false so the legacy policy card takes over', async () => {
      assignmentPoliciesAPI.getInboxPolicy.mockResolvedValue({
        data: { id: 5, name: 'Existing Policy' },
      });

      const wrapper = mountComponent();
      await flushPromises();

      expect(wrapper.vm.assignmentPolicy).toBeTruthy();
      expect(wrapper.vm.showDirectAssignmentModeUI).toBe(false);
    });
  });

  describe('capacity policy visibility', () => {
    it('reports no capacity limit when no policy covers this inbox', async () => {
      const wrapper = mountComponent();
      await flushPromises();

      expect(wrapper.vm.inboxCapacityLimit).toBeUndefined();
    });

    it('navigates to the capacity policy index when none is configured', async () => {
      const wrapper = mountComponent();
      await flushPromises();
      const push = useRouter().push;

      wrapper.vm.navigateToCapacityPolicyIndex();

      expect(push).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'agent_capacity_policy_index' })
      );
    });

    it('resolves the covering policy and limit when this inbox is included', async () => {
      store = createStore({
        getters: {
          'agents/getAgents': () => [],
          'accounts/isFeatureEnabledonAccount': () => () => true,
          'agentCapacityPolicies/getAgentCapacityPolicies': () => [
            {
              id: 9,
              name: 'Support capacity',
              inboxCapacityLimits: [
                { inboxId: inbox.id, conversationLimit: 15 },
              ],
            },
          ],
        },
      });
      dispatchSpy = vi.spyOn(store, 'dispatch').mockResolvedValue();

      const wrapper = mountComponent();
      await flushPromises();

      expect(wrapper.vm.inboxCapacityLimit.conversationLimit).toBe(15);
      expect(wrapper.vm.inboxCapacityPolicy.id).toBe(9);

      const push = useRouter().push;
      wrapper.vm.navigateToCapacityPolicyEdit();

      expect(push).toHaveBeenCalledWith(
        expect.objectContaining({
          name: 'agent_capacity_policy_edit',
          params: expect.objectContaining({ id: 9 }),
        })
      );
    });
  });
});
