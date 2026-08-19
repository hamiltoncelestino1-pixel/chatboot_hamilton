import {
  OPERATOR_TYPES_1,
  OPERATOR_TYPES_2,
  OPERATOR_TYPES_3,
  OPERATOR_TYPES_6,
} from './operators';

export const AUTOMATIONS = {
  message_created: {
    conditions: [
      {
        key: 'message_type',
        name: 'MESSAGE_TYPE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'private_note',
        name: 'PRIVATE_NOTE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'content',
        name: 'MESSAGE_CONTAINS',
        inputType: 'comma_separated_plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'email',
        name: 'EMAIL',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'inbox_id',
        name: 'INBOX',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'status',
        name: 'STATUS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'assignee_id',
        name: 'ASSIGNEE_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'team_id',
        name: 'TEAM_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'priority',
        name: 'PRIORITY',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'conversation_language',
        name: 'CONVERSATION_LANGUAGE',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'phone_number',
        name: 'PHONE_NUMBER',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_6,
      },
      {
        key: 'company_name',
        name: 'COMPANY_NAME',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'labels',
        name: 'LABELS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_3,
      },
    ],
    actions: [
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'assign_team',
        name: 'ASSIGN_TEAM',
      },
      {
        key: 'remove_assigned_agent',
        name: 'REMOVE_ASSIGNED_AGENT',
      },
      {
        key: 'remove_assigned_team',
        name: 'REMOVE_ASSIGNED_TEAM',
      },
      {
        key: 'add_label',
        name: 'ADD_LABEL',
      },
      {
        key: 'remove_label',
        name: 'REMOVE_LABEL',
      },
      {
        key: 'send_email_to_team',
        name: 'SEND_EMAIL_TO_TEAM',
      },
      {
        key: 'send_message',
        name: 'SEND_MESSAGE',
      },
      {
        key: 'send_email_transcript',
        name: 'SEND_EMAIL_TRANSCRIPT',
      },
      {
        key: 'mute_conversation',
        name: 'MUTE_CONVERSATION',
      },
      {
        key: 'snooze_conversation',
        name: 'SNOOZE_CONVERSATION',
      },
      {
        key: 'open_conversation',
        name: 'OPEN_CONVERSATION',
      },
      {
        key: 'pending_conversation',
        name: 'PENDING_CONVERSATION',
      },
      {
        key: 'resolve_conversation',
        name: 'RESOLVE_CONVERSATION',
      },
      {
        key: 'send_webhook_event',
        name: 'SEND_WEBHOOK_EVENT',
      },
      {
        key: 'send_attachment',
        name: 'SEND_ATTACHMENT',
      },
      {
        key: 'create_pipeline_item',
        name: 'CREATE_PIPELINE_ITEM',
      },
      {
        key: 'move_pipeline_item_stage',
        name: 'MOVE_PIPELINE_ITEM_STAGE',
      },
      {
        key: 'assign_pipeline_item_agent',
        name: 'ASSIGN_PIPELINE_ITEM_AGENT',
      },
      {
        key: 'assign_pipeline_item_team',
        name: 'ASSIGN_PIPELINE_ITEM_TEAM',
      },
      {
        key: 'add_pipeline_item_label',
        name: 'ADD_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'remove_pipeline_item_label',
        name: 'REMOVE_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'update_pipeline_item',
        name: 'UPDATE_PIPELINE_ITEM',
      },
      {
        key: 'export_pipeline_item',
        name: 'EXPORT_PIPELINE_ITEM',
      },
    ],
  },
  conversation_created: {
    conditions: [
      {
        key: 'status',
        name: 'STATUS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'browser_language',
        name: 'BROWSER_LANGUAGE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'mail_subject',
        name: 'MAIL_SUBJECT',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'country_code',
        name: 'COUNTRY_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'phone_number',
        name: 'PHONE_NUMBER',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_6,
      },
      {
        key: 'company_name',
        name: 'COMPANY_NAME',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'referer',
        name: 'REFERER_LINK',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'email',
        name: 'EMAIL',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'inbox_id',
        name: 'INBOX',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'conversation_language',
        name: 'CONVERSATION_LANGUAGE',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'priority',
        name: 'PRIORITY',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'labels',
        name: 'LABELS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_3,
      },
    ],
    actions: [
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'assign_team',
        name: 'ASSIGN_TEAM',
      },
      {
        key: 'remove_assigned_agent',
        name: 'REMOVE_ASSIGNED_AGENT',
      },
      {
        key: 'remove_assigned_team',
        name: 'REMOVE_ASSIGNED_TEAM',
      },
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'send_email_to_team',
        name: 'SEND_EMAIL_TO_TEAM',
      },
      {
        key: 'send_message',
        name: 'SEND_MESSAGE',
      },
      {
        key: 'send_email_transcript',
        name: 'SEND_EMAIL_TRANSCRIPT',
      },
      {
        key: 'mute_conversation',
        name: 'MUTE_CONVERSATION',
      },
      {
        key: 'snooze_conversation',
        name: 'SNOOZE_CONVERSATION',
      },
      {
        key: 'pending_conversation',
        name: 'PENDING_CONVERSATION',
      },
      {
        key: 'resolve_conversation',
        name: 'RESOLVE_CONVERSATION',
      },
      {
        key: 'send_webhook_event',
        name: 'SEND_WEBHOOK_EVENT',
      },
      {
        key: 'send_attachment',
        name: 'SEND_ATTACHMENT',
      },
      {
        key: 'create_pipeline_item',
        name: 'CREATE_PIPELINE_ITEM',
      },
      {
        key: 'move_pipeline_item_stage',
        name: 'MOVE_PIPELINE_ITEM_STAGE',
      },
      {
        key: 'assign_pipeline_item_agent',
        name: 'ASSIGN_PIPELINE_ITEM_AGENT',
      },
      {
        key: 'assign_pipeline_item_team',
        name: 'ASSIGN_PIPELINE_ITEM_TEAM',
      },
      {
        key: 'add_pipeline_item_label',
        name: 'ADD_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'remove_pipeline_item_label',
        name: 'REMOVE_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'update_pipeline_item',
        name: 'UPDATE_PIPELINE_ITEM',
      },
      {
        key: 'export_pipeline_item',
        name: 'EXPORT_PIPELINE_ITEM',
      },
    ],
  },
  conversation_updated: {
    conditions: [
      {
        key: 'status',
        name: 'STATUS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'browser_language',
        name: 'BROWSER_LANGUAGE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'mail_subject',
        name: 'MAIL_SUBJECT',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'country_code',
        name: 'COUNTRY_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'referer',
        name: 'REFERER_LINK',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'phone_number',
        name: 'PHONE_NUMBER',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_6,
      },
      {
        key: 'company_name',
        name: 'COMPANY_NAME',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'assignee_id',
        name: 'ASSIGNEE_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'team_id',
        name: 'TEAM_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'email',
        name: 'EMAIL',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'inbox_id',
        name: 'INBOX',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'conversation_language',
        name: 'CONVERSATION_LANGUAGE',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'priority',
        name: 'PRIORITY',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'labels',
        name: 'LABELS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_3,
      },
    ],
    actions: [
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'assign_team',
        name: 'ASSIGN_TEAM',
      },
      {
        key: 'remove_assigned_agent',
        name: 'REMOVE_ASSIGNED_AGENT',
      },
      {
        key: 'remove_assigned_team',
        name: 'REMOVE_ASSIGNED_TEAM',
      },
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'send_email_to_team',
        name: 'SEND_EMAIL_TO_TEAM',
      },
      {
        key: 'send_message',
        name: 'SEND_MESSAGE',
      },
      {
        key: 'send_email_transcript',
        name: 'SEND_EMAIL_TRANSCRIPT',
      },
      {
        key: 'mute_conversation',
        name: 'MUTE_CONVERSATION',
      },
      {
        key: 'snooze_conversation',
        name: 'SNOOZE_CONVERSATION',
      },
      {
        key: 'pending_conversation',
        name: 'PENDING_CONVERSATION',
      },
      {
        key: 'resolve_conversation',
        name: 'RESOLVE_CONVERSATION',
      },
      {
        key: 'send_webhook_event',
        name: 'SEND_WEBHOOK_EVENT',
      },
      {
        key: 'send_attachment',
        name: 'SEND_ATTACHMENT',
      },
      {
        key: 'create_pipeline_item',
        name: 'CREATE_PIPELINE_ITEM',
      },
      {
        key: 'move_pipeline_item_stage',
        name: 'MOVE_PIPELINE_ITEM_STAGE',
      },
      {
        key: 'assign_pipeline_item_agent',
        name: 'ASSIGN_PIPELINE_ITEM_AGENT',
      },
      {
        key: 'assign_pipeline_item_team',
        name: 'ASSIGN_PIPELINE_ITEM_TEAM',
      },
      {
        key: 'add_pipeline_item_label',
        name: 'ADD_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'remove_pipeline_item_label',
        name: 'REMOVE_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'update_pipeline_item',
        name: 'UPDATE_PIPELINE_ITEM',
      },
      {
        key: 'export_pipeline_item',
        name: 'EXPORT_PIPELINE_ITEM',
      },
    ],
  },
  conversation_opened: {
    conditions: [
      {
        key: 'browser_language',
        name: 'BROWSER_LANGUAGE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'email',
        name: 'EMAIL',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'mail_subject',
        name: 'MAIL_SUBJECT',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'country_code',
        name: 'COUNTRY_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'referer',
        name: 'REFERER_LINK',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'assignee_id',
        name: 'ASSIGNEE_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'phone_number',
        name: 'PHONE_NUMBER',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_6,
      },
      {
        key: 'company_name',
        name: 'COMPANY_NAME',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'team_id',
        name: 'TEAM_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'inbox_id',
        name: 'INBOX',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'conversation_language',
        name: 'CONVERSATION_LANGUAGE',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'priority',
        name: 'PRIORITY',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'labels',
        name: 'LABELS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_3,
      },
    ],
    actions: [
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'assign_team',
        name: 'ASSIGN_TEAM',
      },
      {
        key: 'remove_assigned_agent',
        name: 'REMOVE_ASSIGNED_AGENT',
      },
      {
        key: 'remove_assigned_team',
        name: 'REMOVE_ASSIGNED_TEAM',
      },
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'send_email_to_team',
        name: 'SEND_EMAIL_TO_TEAM',
      },
      {
        key: 'send_message',
        name: 'SEND_MESSAGE',
      },
      {
        key: 'send_email_transcript',
        name: 'SEND_EMAIL_TRANSCRIPT',
      },
      {
        key: 'mute_conversation',
        name: 'MUTE_CONVERSATION',
      },
      {
        key: 'snooze_conversation',
        name: 'SNOOZE_CONVERSATION',
      },
      {
        key: 'pending_conversation',
        name: 'PENDING_CONVERSATION',
      },
      {
        key: 'send_webhook_event',
        name: 'SEND_WEBHOOK_EVENT',
      },
      {
        key: 'send_attachment',
        name: 'SEND_ATTACHMENT',
      },
      {
        key: 'create_pipeline_item',
        name: 'CREATE_PIPELINE_ITEM',
      },
      {
        key: 'move_pipeline_item_stage',
        name: 'MOVE_PIPELINE_ITEM_STAGE',
      },
      {
        key: 'assign_pipeline_item_agent',
        name: 'ASSIGN_PIPELINE_ITEM_AGENT',
      },
      {
        key: 'assign_pipeline_item_team',
        name: 'ASSIGN_PIPELINE_ITEM_TEAM',
      },
      {
        key: 'add_pipeline_item_label',
        name: 'ADD_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'remove_pipeline_item_label',
        name: 'REMOVE_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'update_pipeline_item',
        name: 'UPDATE_PIPELINE_ITEM',
      },
      {
        key: 'export_pipeline_item',
        name: 'EXPORT_PIPELINE_ITEM',
      },
    ],
  },
  conversation_resolved: {
    conditions: [
      {
        key: 'browser_language',
        name: 'BROWSER_LANGUAGE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'email',
        name: 'EMAIL',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'mail_subject',
        name: 'MAIL_SUBJECT',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'country_code',
        name: 'COUNTRY_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'referer',
        name: 'REFERER_LINK',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'assignee_id',
        name: 'ASSIGNEE_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'phone_number',
        name: 'PHONE_NUMBER',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_6,
      },
      {
        key: 'company_name',
        name: 'COMPANY_NAME',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'team_id',
        name: 'TEAM_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'inbox_id',
        name: 'INBOX',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'conversation_language',
        name: 'CONVERSATION_LANGUAGE',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
      {
        key: 'priority',
        name: 'PRIORITY',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_1,
      },
    ],
    actions: [
      {
        key: 'assign_agent',
        name: 'ASSIGN_AGENT',
      },
      {
        key: 'assign_team',
        name: 'ASSIGN_TEAM',
      },
      {
        key: 'remove_assigned_agent',
        name: 'REMOVE_ASSIGNED_AGENT',
      },
      {
        key: 'remove_assigned_team',
        name: 'REMOVE_ASSIGNED_TEAM',
      },
      {
        key: 'send_email_to_team',
        name: 'SEND_EMAIL_TO_TEAM',
      },
      {
        key: 'send_message',
        name: 'SEND_MESSAGE',
      },
      {
        key: 'send_email_transcript',
        name: 'SEND_EMAIL_TRANSCRIPT',
      },
      {
        key: 'send_webhook_event',
        name: 'SEND_WEBHOOK_EVENT',
      },
      {
        key: 'send_attachment',
        name: 'SEND_ATTACHMENT',
      },
      {
        key: 'create_pipeline_item',
        name: 'CREATE_PIPELINE_ITEM',
      },
      {
        key: 'move_pipeline_item_stage',
        name: 'MOVE_PIPELINE_ITEM_STAGE',
      },
      {
        key: 'assign_pipeline_item_agent',
        name: 'ASSIGN_PIPELINE_ITEM_AGENT',
      },
      {
        key: 'assign_pipeline_item_team',
        name: 'ASSIGN_PIPELINE_ITEM_TEAM',
      },
      {
        key: 'add_pipeline_item_label',
        name: 'ADD_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'remove_pipeline_item_label',
        name: 'REMOVE_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'update_pipeline_item',
        name: 'UPDATE_PIPELINE_ITEM',
      },
      {
        key: 'export_pipeline_item',
        name: 'EXPORT_PIPELINE_ITEM',
      },
    ],
  },
  // pipeline_item_created/pipeline_item_stage_changed (task 09's native pipeline triggers):
  // stage_id lists every stage of every pipeline in the account rather than cascading from a
  // pipeline_id condition on a sibling row - the generic condition-row component has no way
  // for one row to know another row's selected value, so this is the simplest option that
  // doesn't require new cross-row logic. Combining pipeline_id = X AND stage_id = Y conditions
  // achieves the same result, since the backend already evaluates both with AND.
  pipeline_item_created: {
    conditions: [
      {
        key: 'pipeline_id',
        name: 'PIPELINE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'stage_id',
        name: 'STAGE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'value',
        name: 'VALUE',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'assignee_id',
        name: 'ASSIGNEE_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'team_id',
        name: 'TEAM_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'labels',
        name: 'LABELS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_3,
      },
    ],
    actions: [
      {
        key: 'move_pipeline_item_stage',
        name: 'MOVE_PIPELINE_ITEM_STAGE',
      },
      {
        key: 'assign_pipeline_item_agent',
        name: 'ASSIGN_PIPELINE_ITEM_AGENT',
      },
      {
        key: 'assign_pipeline_item_team',
        name: 'ASSIGN_PIPELINE_ITEM_TEAM',
      },
      {
        key: 'add_pipeline_item_label',
        name: 'ADD_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'remove_pipeline_item_label',
        name: 'REMOVE_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'update_pipeline_item',
        name: 'UPDATE_PIPELINE_ITEM',
      },
      {
        key: 'export_pipeline_item',
        name: 'EXPORT_PIPELINE_ITEM',
      },
      {
        key: 'send_webhook_event',
        name: 'SEND_WEBHOOK_EVENT',
      },
      {
        key: 'create_pipeline_item_task',
        name: 'CREATE_PIPELINE_ITEM_TASK',
      },
    ],
  },
  pipeline_item_stage_changed: {
    conditions: [
      {
        key: 'pipeline_id',
        name: 'PIPELINE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'stage_id',
        name: 'STAGE',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'value',
        name: 'VALUE',
        inputType: 'plain_text',
        filterOperators: OPERATOR_TYPES_2,
      },
      {
        key: 'assignee_id',
        name: 'ASSIGNEE_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'team_id',
        name: 'TEAM_NAME',
        inputType: 'search_select',
        filterOperators: OPERATOR_TYPES_3,
      },
      {
        key: 'labels',
        name: 'LABELS',
        inputType: 'multi_select',
        filterOperators: OPERATOR_TYPES_3,
      },
    ],
    actions: [
      {
        key: 'move_pipeline_item_stage',
        name: 'MOVE_PIPELINE_ITEM_STAGE',
      },
      {
        key: 'assign_pipeline_item_agent',
        name: 'ASSIGN_PIPELINE_ITEM_AGENT',
      },
      {
        key: 'assign_pipeline_item_team',
        name: 'ASSIGN_PIPELINE_ITEM_TEAM',
      },
      {
        key: 'add_pipeline_item_label',
        name: 'ADD_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'remove_pipeline_item_label',
        name: 'REMOVE_PIPELINE_ITEM_LABEL',
      },
      {
        key: 'update_pipeline_item',
        name: 'UPDATE_PIPELINE_ITEM',
      },
      {
        key: 'export_pipeline_item',
        name: 'EXPORT_PIPELINE_ITEM',
      },
      {
        key: 'send_webhook_event',
        name: 'SEND_WEBHOOK_EVENT',
      },
      {
        key: 'create_pipeline_item_task',
        name: 'CREATE_PIPELINE_ITEM_TASK',
      },
    ],
  },
};

export const AUTOMATION_RULE_EVENTS = [
  {
    key: 'conversation_created',
    value: 'CONVERSATION_CREATED',
  },
  {
    key: 'conversation_updated',
    value: 'CONVERSATION_UPDATED',
  },
  {
    key: 'conversation_resolved',
    value: 'CONVERSATION_RESOLVED',
  },
  {
    key: 'message_created',
    value: 'MESSAGE_CREATED',
  },
  {
    key: 'conversation_opened',
    value: 'CONVERSATION_OPENED',
  },
  {
    key: 'pipeline_item_created',
    value: 'PIPELINE_ITEM_CREATED',
  },
  {
    key: 'pipeline_item_stage_changed',
    value: 'PIPELINE_ITEM_STAGE_CHANGED',
  },
];

export const AUTOMATION_ACTION_TYPES = [
  {
    key: 'assign_agent',
    label: 'ASSIGN_AGENT',
    inputType: 'search_select',
  },
  {
    key: 'assign_team',
    label: 'ASSIGN_TEAM',
    inputType: 'search_select',
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
    key: 'send_email_to_team',
    label: 'SEND_EMAIL_TO_TEAM',
    inputType: 'team_message',
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
    key: 'open_conversation',
    label: 'OPEN_CONVERSATION',
    inputType: null,
  },
  {
    key: 'pending_conversation',
    label: 'PENDING_CONVERSATION',
    inputType: null,
  },
  {
    key: 'send_webhook_event',
    label: 'SEND_WEBHOOK_EVENT',
    inputType: 'url',
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
    key: 'add_sla',
    label: 'ADD_SLA',
    inputType: 'search_select',
  },
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
    key: 'export_pipeline_item',
    label: 'EXPORT_PIPELINE_ITEM',
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
    key: 'create_pipeline_item_task',
    label: 'CREATE_PIPELINE_ITEM_TASK',
    inputType: 'pipeline_create_task',
  },
];
