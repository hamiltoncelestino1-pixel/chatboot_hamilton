class AutomationRules::ActionService < ActionService
  include PipelineItemActions

  def initialize(rule, account, conversation)
    super(conversation)
    @rule = rule
    @account = account
    Current.account = @account
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      @conversation.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @rule.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation.reload, params).perform
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end

  def create_pipeline_item(params)
    params = params[0]
    contact = @conversation.contact

    @account.pipeline_items.new(
      contact_id: contact.id,
      conversation_id: @conversation.id,
      pipeline_stage_id: params[:pipeline_stage_id],
      assignee_id: resolve_pipeline_item_assignee_id(params[:assignee_mode]),
      team_id: resolve_pipeline_item_team_id(params[:team_mode]),
      title: params[:title],
      value: params[:value],
      notes: params[:notes]
    ).save!
  end

  def move_pipeline_item_stage(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('move_pipeline_item_stage', params[:pipeline_id]) if item.blank?

    target_stage = move_stage(item, params[:target_stage_id])
    log_invalid_target_stage(params[:target_stage_id], item) if target_stage.blank?
  end

  def assign_pipeline_item_agent(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('assign_pipeline_item_agent', params[:pipeline_id]) if item.blank?

    assign_pipeline_agent(item, resolve_pipeline_item_assignee_id(params[:assignee_mode]))
  end

  def assign_pipeline_item_team(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('assign_pipeline_item_team', params[:pipeline_id]) if item.blank?

    assign_pipeline_team(item, resolve_pipeline_item_team_id(params[:team_mode]))
  end

  def add_pipeline_item_label(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('add_pipeline_item_label', params[:pipeline_id]) if item.blank?

    add_pipeline_label(item, Array(params[:labels]))
  end

  def remove_pipeline_item_label(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('remove_pipeline_item_label', params[:pipeline_id]) if item.blank?

    remove_pipeline_label(item, Array(params[:labels]))
  end

  def update_pipeline_item(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('update_pipeline_item', params[:pipeline_id]) if item.blank?

    update_fields(item, params)
  end

  def export_pipeline_item(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('export_pipeline_item', params[:pipeline_id]) if item.blank?

    target_pipeline = @account.pipelines.find(params[:target_pipeline_id])
    export_to_pipeline(item, target_pipeline, params[:target_stage_id])
  end

  def resolve_pipeline_item_for_conversation(pipeline_id)
    @account.pipeline_items.find_by(pipeline_id: pipeline_id, contact_id: @conversation.contact_id)
  end

  def resolve_pipeline_item_assignee_id(assignee_mode)
    return @conversation.assignee_id if assignee_mode == 'conversation_assignee'
    return nil if assignee_mode.blank? || assignee_mode == 'none'

    assignee_mode
  end

  def resolve_pipeline_item_team_id(team_mode)
    return @conversation.team_id if team_mode == 'conversation_team'
    return nil if team_mode.blank? || team_mode == 'none'

    team_mode
  end

  def log_no_pipeline_item(action_name, pipeline_id)
    Rails.logger.info(
      "[AutomationRules::ActionService] #{action_name}: no pipeline_item found for pipeline_id=#{pipeline_id}, " \
      "contact_id=#{@conversation.contact_id}"
    )
  end

  def log_invalid_target_stage(target_stage_id, item)
    Rails.logger.info(
      "[AutomationRules::ActionService] target_stage_id=#{target_stage_id} does not belong to " \
      "pipeline_item##{item.id}'s pipeline (pipeline_id=#{item.pipeline_id})"
    )
  end
end
