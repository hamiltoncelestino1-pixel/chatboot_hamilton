require 'rails_helper'

RSpec.describe PipelineItemActions do
  # Both AutomationRules::ActionService (task 04) and Macros::PipelineExecutionService
  # (task 06) include this module; its business logic is asserted once here instead of
  # being duplicated across both services' specs.
  let(:includer) { Class.new { include PipelineItemActions }.new }

  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:start_stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
  let(:won_stage) { pipeline.pipeline_stages.find_by(stage_type: :won) }
  let(:item) { create(:pipeline_item, pipeline_stage: start_stage, account: account, contact: contact) }

  describe '#move_stage' do
    it 'moves the item to the target stage and appends it to the end of the column' do
      create(:pipeline_item, pipeline_stage: won_stage, account: account, position: 3)

      result = includer.move_stage(item, won_stage.id)

      expect(result).to eq(won_stage)
      expect(item.reload.pipeline_stage_id).to eq(won_stage.id)
      expect(item.position).to eq(4)
    end

    it 'returns nil and leaves the item untouched when target_stage_id belongs to a different pipeline' do
      other_stage = create(:pipeline_stage, account: account)

      result = includer.move_stage(item, other_stage.id)

      expect(result).to be_nil
      expect(item.reload.pipeline_stage_id).to eq(start_stage.id)
    end
  end

  describe '#assign_pipeline_agent' do
    it 'sets the assignee_id' do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: pipeline, user: agent)

      includer.assign_pipeline_agent(item, agent.id)

      expect(item.reload.assignee_id).to eq(agent.id)
    end

    it 'clears the assignee_id when given nil' do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: pipeline, user: agent)
      item.update!(assignee_id: agent.id)

      includer.assign_pipeline_agent(item, nil)

      expect(item.reload.assignee_id).to be_nil
    end
  end

  describe '#assign_pipeline_team' do
    it 'sets the team_id' do
      team = create(:team, account: account)

      includer.assign_pipeline_team(item, team.id)

      expect(item.reload.team_id).to eq(team.id)
    end

    it 'clears the team_id when given nil' do
      team = create(:team, account: account)
      item.update!(team_id: team.id)

      includer.assign_pipeline_team(item, nil)

      expect(item.reload.team_id).to be_nil
    end

    it 'logs and does not assign a team that belongs to another account' do
      other_account_team = create(:team, account: create(:account))
      allow(Rails.logger).to receive(:info)

      includer.assign_pipeline_team(item, other_account_team.id)

      expect(item.reload.team_id).to be_nil
      expect(Rails.logger).to have_received(:info).with(/does not belong to/)
    end
  end

  describe '#add_pipeline_label' do
    it 'adds the given labels to the item' do
      create(:label, account: account, title: 'quente', label_type: :pipeline_label)

      includer.add_pipeline_label(item, ['quente'])

      expect(item.reload.label_list).to include('quente')
    end

    it 'is a no-op when labels are blank' do
      expect { includer.add_pipeline_label(item, []) }.not_to(change { item.reload.label_list })
    end
  end

  describe '#remove_pipeline_label' do
    it 'removes the given labels from the item' do
      create(:label, account: account, title: 'quente', label_type: :pipeline_label)
      create(:label, account: account, title: 'frio', label_type: :pipeline_label)
      item.update!(label_list: %w[quente frio])

      includer.remove_pipeline_label(item, ['quente'])

      expect(item.reload.label_list).to contain_exactly('frio')
    end
  end

  describe '#update_fields' do
    it 'updates only the given subset of title/value/notes' do
      item.update!(notes: 'keep me')

      includer.update_fields(item, { title: 'New title', value: 300 })
      item.reload

      expect(item.title).to eq('New title')
      expect(item.value.to_f).to eq(300.0)
      expect(item.notes).to eq('keep me')
    end

    it 'is a no-op when no recognized fields are present' do
      item.update!(title: 'Original')

      includer.update_fields(item, { unrelated: 'ignored' })

      expect(item.reload.title).to eq('Original')
    end
  end

  describe '#export_to_pipeline' do
    it 'delegates to Pipelines::ExportItemService' do
      target_pipeline = create(:pipeline, account: account)
      target_stage = target_pipeline.pipeline_stages.find_by(stage_type: :start)

      includer.export_to_pipeline(item, target_pipeline, target_stage.id)

      expect(item.reload.pipeline_stage_id).to eq(target_stage.id)
    end
  end
end
