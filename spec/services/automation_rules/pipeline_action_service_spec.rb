require 'rails_helper'

RSpec.describe AutomationRules::PipelineActionService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:start_stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
  let(:won_stage) { pipeline.pipeline_stages.find_by(stage_type: :won) }
  let(:item) { create(:pipeline_item, pipeline_stage: start_stage, account: account, contact: contact) }
  let!(:rule) { create(:automation_rule, account: account, event_name: 'pipeline_item_stage_changed', conditions: [], actions: []) }

  after do
    Current.reset
  end

  describe '#perform with move_pipeline_item_stage action' do
    it 'moves the item to the target stage' do
      rule.update!(actions: [{ action_name: 'move_pipeline_item_stage', action_params: [{ target_stage_id: won_stage.id }] }])

      described_class.new(rule, account, item).perform

      expect(item.reload.pipeline_stage_id).to eq(won_stage.id)
    end

    it 'logs and does not raise when the target stage does not belong to the pipeline' do
      other_stage = create(:pipeline_stage, account: account)
      rule.update!(actions: [{ action_name: 'move_pipeline_item_stage', action_params: [{ target_stage_id: other_stage.id }] }])

      expect { described_class.new(rule, account, item).perform }.not_to raise_error
      expect(item.reload.pipeline_stage_id).to eq(start_stage.id)
    end
  end

  describe '#perform with assign_pipeline_item_agent action' do
    it 'assigns the given agent' do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: pipeline, user: agent)
      rule.update!(actions: [{ action_name: 'assign_pipeline_item_agent', action_params: [{ assignee_mode: agent.id.to_s }] }])

      described_class.new(rule, account, item).perform

      expect(item.reload.assignee_id).to eq(agent.id)
    end

    it 'assigns an administrator who is not an explicit pipeline member, without raising' do
      admin = create(:user, account: account, role: :administrator)
      rule.update!(actions: [{ action_name: 'assign_pipeline_item_agent', action_params: [{ assignee_mode: admin.id.to_s }] }])

      expect { described_class.new(rule, account, item).perform }.not_to raise_error

      expect(item.reload.assignee_id).to eq(admin.id)
      expect(Current.account).to be_nil
    end
  end

  describe '#perform with assign_pipeline_item_team action' do
    it 'assigns the given team' do
      team = create(:team, account: account)
      rule.update!(actions: [{ action_name: 'assign_pipeline_item_team', action_params: [{ team_mode: team.id.to_s }] }])

      described_class.new(rule, account, item).perform

      expect(item.reload.team_id).to eq(team.id)
    end
  end

  describe '#perform with add_pipeline_item_label action' do
    it 'adds the given labels' do
      create(:label, account: account, title: 'quente', label_type: :pipeline_label)
      rule.update!(actions: [{ action_name: 'add_pipeline_item_label', action_params: [{ labels: ['quente'] }] }])

      described_class.new(rule, account, item).perform

      expect(item.reload.label_list).to include('quente')
    end
  end

  describe '#perform with remove_pipeline_item_label action' do
    it 'removes the given labels' do
      create(:label, account: account, title: 'quente', label_type: :pipeline_label)
      item.label_list = ['quente']
      item.save!(validate: false)
      rule.update!(actions: [{ action_name: 'remove_pipeline_item_label', action_params: [{ labels: ['quente'] }] }])

      described_class.new(rule, account, item).perform

      expect(item.reload.label_list).not_to include('quente')
    end
  end

  describe '#perform with update_pipeline_item action' do
    it 'updates the given subset of fields' do
      rule.update!(actions: [{ action_name: 'update_pipeline_item', action_params: [{ title: 'Updated', value: 500 }] }])

      described_class.new(rule, account, item).perform
      item.reload

      expect(item.title).to eq('Updated')
      expect(item.value.to_f).to eq(500.0)
    end
  end

  describe '#perform with export_pipeline_item action' do
    it 'exports the item to the target pipeline and stage' do
      target_pipeline = create(:pipeline, account: account)
      target_stage = target_pipeline.pipeline_stages.find_by(stage_type: :start)
      rule.update!(actions: [{
                     action_name: 'export_pipeline_item',
                     action_params: [{ target_pipeline_id: target_pipeline.id, target_stage_id: target_stage.id }]
                   }])

      described_class.new(rule, account, item).perform

      expect(item.reload.pipeline_stage_id).to eq(target_stage.id)
    end
  end

  describe 'per-action rescue' do
    it 'logs via ChatwootExceptionTracker and keeps running the remaining actions when one action fails' do
      outsider = create(:user, account: account, role: :agent)
      team = create(:team, account: account)
      rule.update!(actions: [
                     { action_name: 'assign_pipeline_item_agent', action_params: [{ assignee_mode: outsider.id.to_s }] },
                     { action_name: 'assign_pipeline_item_team', action_params: [{ team_mode: team.id.to_s }] }
                   ])

      expect(ChatwootExceptionTracker).to receive(:new).with(an_instance_of(ActiveRecord::RecordInvalid), account: account).and_call_original
      described_class.new(rule, account, item).perform

      expect(item.reload.assignee_id).to be_nil
      expect(item.reload.team_id).to eq(team.id)
    end
  end
end
