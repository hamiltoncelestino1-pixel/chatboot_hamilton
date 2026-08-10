require 'rails_helper'

RSpec.describe Macros::PipelineExecutionService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:start_stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
  let(:won_stage) { pipeline.pipeline_stages.find_by(stage_type: :won) }
  let(:item) { create(:pipeline_item, pipeline_stage: start_stage, account: account, contact: contact) }

  def macro_with(actions)
    create(:macro, account: account, created_by: admin, updated_by: admin, macro_type: :pipeline_item, actions: actions)
  end

  describe '#perform with move_pipeline_item_stage action' do
    it 'moves the item to the target stage' do
      macro = macro_with([{ action_name: 'move_pipeline_item_stage', action_params: [{ target_stage_id: won_stage.id }] }])

      described_class.new(macro, item, admin).perform

      expect(item.reload.pipeline_stage_id).to eq(won_stage.id)
    end
  end

  describe '#perform with assign_pipeline_item_agent action' do
    it 'assigns the given agent' do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: pipeline, user: agent)
      macro = macro_with([{ action_name: 'assign_pipeline_item_agent', action_params: [{ assignee_mode: agent.id.to_s }] }])

      described_class.new(macro, item, admin).perform

      expect(item.reload.assignee_id).to eq(agent.id)
    end

    it 'clears the assignee when assignee_mode is none' do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: pipeline, user: agent)
      item.update!(assignee_id: agent.id)
      macro = macro_with([{ action_name: 'assign_pipeline_item_agent', action_params: [{ assignee_mode: 'none' }] }])

      described_class.new(macro, item, admin).perform

      expect(item.reload.assignee_id).to be_nil
    end
  end

  describe '#perform with assign_pipeline_item_team action' do
    it 'assigns the given team' do
      team = create(:team, account: account)
      macro = macro_with([{ action_name: 'assign_pipeline_item_team', action_params: [{ team_mode: team.id.to_s }] }])

      described_class.new(macro, item, admin).perform

      expect(item.reload.team_id).to eq(team.id)
    end
  end

  describe '#perform with add_pipeline_item_label action' do
    it 'adds the given labels' do
      create(:label, account: account, title: 'quente', label_type: :pipeline_label)
      macro = macro_with([{ action_name: 'add_pipeline_item_label', action_params: [{ labels: ['quente'] }] }])

      described_class.new(macro, item, admin).perform

      expect(item.reload.label_list).to include('quente')
    end
  end

  describe '#perform with remove_pipeline_item_label action' do
    it 'removes the given labels' do
      create(:label, account: account, title: 'quente', label_type: :pipeline_label)
      item.update!(label_list: ['quente'])
      macro = macro_with([{ action_name: 'remove_pipeline_item_label', action_params: [{ labels: ['quente'] }] }])

      described_class.new(macro, item, admin).perform

      expect(item.reload.label_list).not_to include('quente')
    end
  end

  describe '#perform with update_pipeline_item action' do
    it 'updates the given subset of fields' do
      macro = macro_with([{ action_name: 'update_pipeline_item', action_params: [{ title: 'Updated', value: 500 }] }])

      described_class.new(macro, item, admin).perform
      item.reload

      expect(item.title).to eq('Updated')
      expect(item.value.to_f).to eq(500.0)
    end
  end

  describe '#perform with export_pipeline_item action' do
    it 'exports the item to the target pipeline and stage' do
      target_pipeline = create(:pipeline, account: account)
      target_stage = target_pipeline.pipeline_stages.find_by(stage_type: :start)
      macro = macro_with([{
                           action_name: 'export_pipeline_item',
                           action_params: [{ target_pipeline_id: target_pipeline.id, target_stage_id: target_stage.id }]
                         }])

      described_class.new(macro, item, admin).perform

      expect(item.reload.pipeline_stage_id).to eq(target_stage.id)
    end
  end

  describe '#perform with send_webhook_event action' do
    it 'sends the webhook with the pipeline item data and the macro event label' do
      macro = macro_with([{ action_name: 'send_webhook_event', action_params: ['https://example.com'] }])

      expect(WebhookJob).to receive(:perform_later).with(
        'https://example.com',
        hash_including(id: item.id, event: 'macro.executed')
      )
      described_class.new(macro, item, admin).perform
    end

    it 'does not send the webhook when the url is blank' do
      macro = macro_with([{ action_name: 'send_webhook_event', action_params: [] }])

      expect(WebhookJob).not_to receive(:perform_later)
      described_class.new(macro, item, admin).perform
    end
  end

  describe '#perform with a conversation action (add_label)' do
    it 'applies the action to the linked conversation' do
      conversation = create(:conversation, account: account, contact: contact)
      item.update!(conversation: conversation)
      macro = macro_with([{ action_name: 'add_label', action_params: %w[quente] }])

      described_class.new(macro, item, admin).perform

      expect(conversation.reload.label_list).to include('quente')
    end

    it 'does nothing and does not raise when the card has no linked conversation' do
      expect(item.conversation).to be_nil
      macro = macro_with([{ action_name: 'add_label', action_params: %w[quente] }])

      expect { described_class.new(macro, item, admin).perform }.not_to raise_error
    end
  end

  describe 'per-action rescue' do
    it 'logs via ChatwootExceptionTracker and keeps running the remaining actions when one action fails' do
      # Not a pipeline member, so assigning them violates PipelineItem's
      # assignee_must_be_pipeline_member validation and raises RecordInvalid.
      outsider = create(:user, account: account, role: :agent)
      team = create(:team, account: account)

      macro = macro_with([
                           { action_name: 'assign_pipeline_item_agent', action_params: [{ assignee_mode: outsider.id.to_s }] },
                           { action_name: 'assign_pipeline_item_team', action_params: [{ team_mode: team.id.to_s }] }
                         ])

      expect(ChatwootExceptionTracker).to receive(:new).with(an_instance_of(ActiveRecord::RecordInvalid), account: account).and_call_original
      described_class.new(macro, item, admin).perform

      expect(item.reload.assignee_id).to be_nil
      expect(item.reload.team_id).to eq(team.id)
    end
  end
end
