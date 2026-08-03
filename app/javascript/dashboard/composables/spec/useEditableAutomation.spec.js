import { useEditableAutomation } from '../useEditableAutomation';
import useAutomationValues from '../useAutomationValues';

vi.mock('../useAutomationValues');

describe('useEditableAutomation', () => {
  beforeEach(() => {
    useAutomationValues.mockReturnValue({
      getConditionDropdownValues: vi.fn(attributeKey => {
        if (attributeKey === 'private_note') {
          return [
            { id: true, name: 'True' },
            { id: false, name: 'False' },
          ];
        }

        return [];
      }),
      getActionDropdownValues: vi.fn(actionName => {
        if (actionName === 'assign_agent') {
          return [
            { id: 'nil', name: 'None' },
            {
              id: 'last_responding_agent',
              name: 'Last Responding Agent',
            },
            { id: 1, name: 'Agent 1' },
          ];
        }

        return [];
      }),
    });
  });

  it('rehydrates boolean conditions as a single selected option', () => {
    const automation = {
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'private_note',
          filter_operator: 'equal_to',
          values: [false],
          query_operator: null,
        },
      ],
      actions: [],
    };
    const automationTypes = {
      message_created: {
        conditions: [{ key: 'private_note', inputType: 'search_select' }],
      },
    };

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], automationTypes, []);

    expect(result.conditions).toEqual([
      {
        attribute_key: 'private_note',
        filter_operator: 'equal_to',
        values: { id: false, name: 'False' },
        query_operator: 'and',
      },
    ]);
  });

  it('rehydrates last responding agent as a selected action option', () => {
    const automation = {
      event_name: 'conversation_created',
      conditions: [],
      actions: [
        {
          action_name: 'assign_agent',
          action_params: ['last_responding_agent'],
        },
      ],
    };
    const automationActionTypes = [
      { key: 'assign_agent', inputType: 'search_select' },
    ];

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], {}, automationActionTypes);

    expect(result.actions).toEqual([
      {
        action_name: 'assign_agent',
        action_params: [
          {
            id: 'last_responding_agent',
            name: 'Last Responding Agent',
          },
        ],
      },
    ]);
  });

  it('unwraps pipeline action params from their persisted array-of-one', () => {
    const automation = {
      event_name: 'conversation_created',
      conditions: [],
      actions: [
        {
          action_name: 'create_pipeline_item',
          action_params: [
            {
              pipeline_id: 5,
              pipeline_stage_id: 12,
              assignee_mode: 'conversation_assignee',
            },
          ],
        },
      ],
    };
    const automationActionTypes = [
      { key: 'create_pipeline_item', inputType: 'pipeline_create_item' },
    ];

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], {}, automationActionTypes);

    expect(result.actions).toEqual([
      {
        action_name: 'create_pipeline_item',
        action_params: {
          pipeline_id: 5,
          pipeline_stage_id: 12,
          assignee_mode: 'conversation_assignee',
        },
      },
    ]);
  });

  it('leaves a freshly reset pipeline action untouched (empty array, not yet configured)', () => {
    const automation = {
      event_name: 'conversation_created',
      conditions: [],
      actions: [
        {
          action_name: 'move_pipeline_item_stage',
          action_params: [],
        },
      ],
    };
    const automationActionTypes = [
      { key: 'move_pipeline_item_stage', inputType: 'pipeline_stage_select' },
    ];

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], {}, automationActionTypes);

    expect(result.actions).toEqual([
      { action_name: 'move_pipeline_item_stage', action_params: [] },
    ]);
  });
});
