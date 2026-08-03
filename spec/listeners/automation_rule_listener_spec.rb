require 'rails_helper'

describe AutomationRuleListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:conditions_filter_service) { double }
  let(:condition_match) { double }
  let(:action_service) { double }

  before do
    allow(AutomationRules::ConditionsFilterService).to receive(:new).and_return(conditions_filter_service)
    allow(conditions_filter_service).to receive(:perform).and_return(condition_match)
    allow(AutomationRules::ActionService).to receive(:new).and_return(action_service)
    allow(action_service).to receive(:perform)
  end

  describe 'conversation_created' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_created', account: account) }
    let(:event) do
      Events::Base.new('conversation_created', Time.zone.now, { conversation: conversation,
                                                                changed_attributes: { status: %w[nil Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_created', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conversation has auto_reply in additional_attributes' do
        conversation.additional_attributes = { 'auto_reply' => true }
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'conversation_updated' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_updated', account: account) }
    let(:event) do
      Events::Base.new('conversation_updated', Time.zone.now, { conversation: conversation,
                                                                changed_attributes: { status: %w[Resolved Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_updated', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_updated(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'conversation_opened' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_opened', account: account) }
    let(:event) do
      Events::Base.new('conversation_opened', Time.zone.now, { conversation: conversation,
                                                               changed_attributes: { status: %w[Resolved Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_opened', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_opened(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'conversation_resolved' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'conversation_resolved', account: account) }
    let(:event) do
      Events::Base.new('conversation_resolved', Time.zone.now, { conversation: conversation,
                                                                 changed_attributes: { status: %w[Snoozed Open] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'conversation_resolved', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.conversation_resolved(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end
    end
  end

  describe 'message_created' do
    let!(:automation_rule) { create(:automation_rule, event_name: 'message_created', account: account) }
    let!(:message) { create(:message, account: account, conversation: conversation) }
    let(:event) do
      Events::Base.new('message_created', Time.zone.now, { message: message,
                                                           changed_attributes: { content: %w[nil Hi] } })
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::ActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'calls AutomationRules::ActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'message_created', account: account)
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).to have_received(:new).twice
      end

      it 'does not call AutomationRules::ActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if message is activity message' do
        message.update!(message_type: 'activity')
        allow(condition_match).to receive(:present?).and_return(true)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if message is auto reply email' do
        email_channel = create(:channel_email, account: account)
        email_inbox = create(:inbox, channel: email_channel, account: account)
        email_conversation = create(:conversation, inbox: email_inbox, account: account)
        email_message = create(:message, conversation: email_conversation, account: account, content_attributes: { email: { auto_reply: true } })
        email_event = Events::Base.new('message_created', Time.zone.now, { message: email_message })
        allow(condition_match).to receive(:present?).and_return(true)

        listener.message_created(email_event)
        expect(AutomationRules::ActionService).not_to have_received(:new)
      end

      it 'calls AutomationRules::ActionService if message is a private note' do
        message.update!(private: true)
        allow(condition_match).to receive(:present?).and_return(true)

        listener.message_created(event)

        expect(AutomationRules::ActionService).to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'does not call AutomationRules::ActionService if conditions do not match based on content' do
        message.update!(processed_message_content: 'hi', content: "hi\n\nhello")
        allow(condition_match).to receive(:present?).and_return(false)
        listener.message_created(event)
        expect(AutomationRules::ActionService).not_to have_received(:new).with(automation_rule, account, conversation)
      end

      it 'passes conversation attributes to conditions filter service' do
        conversation.update!(status: :open, priority: :high)
        listener.message_created(event)
        expect(AutomationRules::ConditionsFilterService).to have_received(:new).with(
          automation_rule,
          conversation,
          { message: message, changed_attributes: { content: %w[nil Hi] } }
        )
      end
    end
  end

  describe 'pipeline_item_created' do
    let(:pipeline) { create(:pipeline, account: account) }
    let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
    let(:pipeline_item) { create(:pipeline_item, pipeline_stage: stage, account: account) }
    let!(:automation_rule) { create(:automation_rule, event_name: 'pipeline_item_created', account: account) }
    let(:event) { Events::Base.new('pipeline_item_created', Time.zone.now, { pipeline_item: pipeline_item }) }

    before do
      allow(AutomationRules::PipelineConditionsFilterService).to receive(:new).and_return(conditions_filter_service)
      allow(AutomationRules::PipelineActionService).to receive(:new).and_return(action_service)
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::PipelineActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.pipeline_item_created(event)
        expect(AutomationRules::PipelineActionService).to have_received(:new).with(automation_rule, account, pipeline_item)
      end

      it 'does not call AutomationRules::PipelineActionService if conditions do not match' do
        allow(condition_match).to receive(:present?).and_return(false)
        listener.pipeline_item_created(event)
        expect(AutomationRules::PipelineActionService).not_to have_received(:new)
      end

      it 'does not call AutomationRules::PipelineActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.pipeline_item_created(event)
        expect(AutomationRules::PipelineActionService).not_to have_received(:new)
      end
    end
  end

  describe 'pipeline_item_stage_changed' do
    let(:pipeline) { create(:pipeline, account: account) }
    let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
    let(:won_stage) { pipeline.pipeline_stages.find_by(stage_type: :won) }
    let(:pipeline_item) { create(:pipeline_item, pipeline_stage: won_stage, account: account) }
    let!(:automation_rule) { create(:automation_rule, event_name: 'pipeline_item_stage_changed', account: account) }
    let(:event) do
      Events::Base.new('pipeline_item_stage_changed', Time.zone.now, { pipeline_item: pipeline_item, previous_stage_id: stage.id })
    end

    before do
      allow(AutomationRules::PipelineConditionsFilterService).to receive(:new).and_return(conditions_filter_service)
      allow(AutomationRules::PipelineActionService).to receive(:new).and_return(action_service)
    end

    context 'when matching rules are present' do
      it 'calls AutomationRules::PipelineActionService if conditions match' do
        allow(condition_match).to receive(:present?).and_return(true)
        listener.pipeline_item_stage_changed(event)
        expect(AutomationRules::PipelineActionService).to have_received(:new).with(automation_rule, account, pipeline_item)
      end

      it 'does not call AutomationRules::PipelineActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(condition_match).to receive(:present?).and_return(true)
        listener.pipeline_item_stage_changed(event)
        expect(AutomationRules::PipelineActionService).not_to have_received(:new)
      end
    end
  end

  describe 'anti-loop guard across a 2-rule pipeline cycle' do
    include ActiveJob::TestHelper

    let!(:pipeline) { create(:pipeline, account: account) }
    let!(:start_stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
    let!(:won_stage) { pipeline.pipeline_stages.find_by(stage_type: :won) }

    before do
      # Rule A: a new card moves straight to won_stage.
      create(:automation_rule, account: account, event_name: 'pipeline_item_created', conditions: [],
                               actions: [{ 'action_name' => 'move_pipeline_item_stage', 'action_params' => [{ 'target_stage_id' => won_stage.id }] }])
      # Rule B: whenever a card's stage changes, move it back to start_stage.
      create(:automation_rule, account: account, event_name: 'pipeline_item_stage_changed', conditions: [],
                               actions: [
                                 { 'action_name' => 'move_pipeline_item_stage', 'action_params' => [{ 'target_stage_id' => start_stage.id }] }
                               ])
    end

    it 'runs rule A once and stops before rule B, instead of looping' do
      item = nil
      perform_enqueued_jobs do
        item = create(:pipeline_item, pipeline_stage: start_stage, account: account)
      end

      # Rule A ran (unblocked: the creating event was not performed_by an automation rule).
      # Rule B would have moved it back to start_stage, but the guard blocks it because the
      # stage_changed event it would react to was itself performed_by rule_a.
      expect(item.reload.pipeline_stage_id).to eq(won_stage.id)
    end
  end
end
