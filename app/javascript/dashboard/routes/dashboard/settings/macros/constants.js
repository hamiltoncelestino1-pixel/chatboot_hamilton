export const MACRO_ACTION_TYPES = [
  {
    key: 'assign_team',
    label: 'ASSIGN_TEAM',
    inputType: 'search_select',
  },
  {
    key: 'assign_agent',
    label: 'ASSIGN_AGENT',
    inputType: 'search_select',
  },
  {
    key: 'add_label',
    label: 'ADD_LABEL',
    inputType: 'multi_select',
  },
  {
    key: 'remove_label',
    label: 'REMOVE_LABEL',
    inputType: 'multi_select',
  },
  {
    key: 'remove_assigned_agent',
    label: 'REMOVE_ASSIGNED_AGENT',
    inputType: null,
  },
  {
    key: 'remove_assigned_team',
    label: 'REMOVE_ASSIGNED_TEAM',
    inputType: null,
  },
  {
    key: 'send_email_transcript',
    label: 'SEND_EMAIL_TRANSCRIPT',
    inputType: 'email',
  },
  {
    key: 'mute_conversation',
    label: 'MUTE_CONVERSATION',
    inputType: null,
  },
  {
    key: 'snooze_conversation',
    label: 'SNOOZE_CONVERSATION',
    inputType: null,
  },
  {
    key: 'resolve_conversation',
    label: 'RESOLVE_CONVERSATION',
    inputType: null,
  },
  {
    key: 'send_attachment',
    label: 'SEND_ATTACHMENT',
    inputType: 'attachment',
  },
  {
    key: 'send_message',
    label: 'SEND_MESSAGE',
    inputType: 'textarea',
  },
  {
    key: 'add_private_note',
    label: 'ADD_PRIVATE_NOTE',
    inputType: 'textarea',
  },
  {
    key: 'change_priority',
    label: 'CHANGE_PRIORITY',
    inputType: 'search_select',
  },
  {
    key: 'send_webhook_event',
    label: 'SEND_WEBHOOK_EVENT',
    inputType: 'url',
  },
  // Pipeline actions (pipeline_tasks/26): a conversation macro can also create/move/
  // assign/label/update/export a pipeline card linked to the contact, reusing the same
  // action names and inputTypes already used by PIPELINE_MACRO_ACTION_TYPES/
  // AUTOMATION_ACTION_TYPES below.
  {
    key: 'create_pipeline_item',
    label: 'CREATE_PIPELINE_ITEM',
    inputType: 'pipeline_create_item',
  },
  {
    key: 'move_pipeline_item_stage',
    label: 'MOVE_PIPELINE_ITEM_STAGE',
    inputType: 'pipeline_stage_select',
  },
  {
    key: 'assign_pipeline_item_agent',
    label: 'ASSIGN_PIPELINE_ITEM_AGENT',
    inputType: 'pipeline_assignee_select',
  },
  {
    key: 'assign_pipeline_item_team',
    label: 'ASSIGN_PIPELINE_ITEM_TEAM',
    inputType: 'pipeline_assignee_select',
  },
  {
    key: 'add_pipeline_item_label',
    label: 'ADD_PIPELINE_ITEM_LABEL',
    inputType: 'pipeline_label_select',
  },
  {
    key: 'remove_pipeline_item_label',
    label: 'REMOVE_PIPELINE_ITEM_LABEL',
    inputType: 'pipeline_label_select',
  },
  {
    key: 'update_pipeline_item',
    label: 'UPDATE_PIPELINE_ITEM',
    inputType: 'pipeline_update_fields',
  },
  {
    key: 'export_pipeline_item',
    label: 'EXPORT_PIPELINE_ITEM',
    inputType: 'pipeline_stage_select',
  },
];

// No create_pipeline_item here: a macro always runs against a card that already
// exists (it's the target of the execution), per the decision in pipeline_tasks/06.
export const PIPELINE_MACRO_ACTION_TYPES = [
  {
    key: 'move_pipeline_item_stage',
    label: 'MOVE_PIPELINE_ITEM_STAGE',
    inputType: 'pipeline_stage_select',
  },
  {
    key: 'assign_pipeline_item_agent',
    label: 'ASSIGN_PIPELINE_ITEM_AGENT',
    inputType: 'pipeline_assignee_select',
  },
  {
    key: 'assign_pipeline_item_team',
    label: 'ASSIGN_PIPELINE_ITEM_TEAM',
    inputType: 'pipeline_assignee_select',
  },
  {
    key: 'add_pipeline_item_label',
    label: 'ADD_PIPELINE_ITEM_LABEL',
    inputType: 'pipeline_label_select',
  },
  {
    key: 'remove_pipeline_item_label',
    label: 'REMOVE_PIPELINE_ITEM_LABEL',
    inputType: 'pipeline_label_select',
  },
  {
    key: 'update_pipeline_item',
    label: 'UPDATE_PIPELINE_ITEM',
    inputType: 'pipeline_update_fields',
  },
  {
    key: 'export_pipeline_item',
    label: 'EXPORT_PIPELINE_ITEM',
    inputType: 'pipeline_stage_select',
  },
  {
    key: 'send_webhook_event',
    label: 'SEND_WEBHOOK_EVENT',
    inputType: 'url',
  },
  // Conversation actions (pipeline_tasks/27): a pipeline macro can also run these on the
  // card's linked conversation, reusing the same action names and inputTypes already used
  // by MACRO_ACTION_TYPES above.
  {
    key: 'send_message',
    label: 'SEND_MESSAGE',
    inputType: 'textarea',
  },
  {
    key: 'add_label',
    label: 'ADD_LABEL',
    inputType: 'multi_select',
  },
  {
    key: 'assign_team',
    label: 'ASSIGN_TEAM',
    inputType: 'search_select',
  },
  {
    key: 'assign_agent',
    label: 'ASSIGN_AGENT',
    inputType: 'search_select',
  },
  {
    key: 'mute_conversation',
    label: 'MUTE_CONVERSATION',
    inputType: null,
  },
  {
    key: 'remove_label',
    label: 'REMOVE_LABEL',
    inputType: 'multi_select',
  },
  {
    key: 'remove_assigned_agent',
    label: 'REMOVE_ASSIGNED_AGENT',
    inputType: null,
  },
  {
    key: 'remove_assigned_team',
    label: 'REMOVE_ASSIGNED_TEAM',
    inputType: null,
  },
  {
    key: 'resolve_conversation',
    label: 'RESOLVE_CONVERSATION',
    inputType: null,
  },
  {
    key: 'snooze_conversation',
    label: 'SNOOZE_CONVERSATION',
    inputType: null,
  },
  {
    key: 'change_priority',
    label: 'CHANGE_PRIORITY',
    inputType: 'search_select',
  },
  {
    key: 'send_email_transcript',
    label: 'SEND_EMAIL_TRANSCRIPT',
    inputType: 'email',
  },
  {
    key: 'send_attachment',
    label: 'SEND_ATTACHMENT',
    inputType: 'attachment',
  },
  {
    key: 'add_private_note',
    label: 'ADD_PRIVATE_NOTE',
    inputType: 'textarea',
  },
];
