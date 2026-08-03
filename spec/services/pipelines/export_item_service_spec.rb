# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipelines::ExportItemService do
  let(:account) { create(:account) }
  let(:source_pipeline) { create(:pipeline, account: account) }
  let(:source_stage) { create(:pipeline_stage, pipeline: source_pipeline, account: account) }
  let(:target_pipeline) { create(:pipeline, account: account) }
  let(:target_stage) { create(:pipeline_stage, pipeline: target_pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }
  let!(:item) do
    create(:pipeline_item,
           pipeline_stage: source_stage,
           account: account,
           contact: contact,
           title: 'Test Card',
           value: 500.0,
           notes: 'Some notes')
  end

  def build_service(target_stage_id: target_stage.id)
    described_class.new(
      pipeline_item: item,
      target_pipeline: target_pipeline,
      target_stage_id: target_stage_id
    )
  end

  describe '#perform' do
    it 'moves the item to the target stage without creating a new record' do
      expect { build_service.perform }.not_to change(PipelineItem, :count)
      expect(item.reload.pipeline_stage_id).to eq(target_stage.id)
    end

    it 'preserves title, value, notes and contact' do
      build_service.perform
      item.reload
      expect(item.title).to eq('Test Card')
      expect(item.value.to_f).to eq(500.0)
      expect(item.notes).to eq('Some notes')
      expect(item.contact_id).to eq(contact.id)
    end

    it 'positions the item at the end of the target stage' do
      create(:pipeline_item, pipeline_stage: target_stage, account: account, position: 3)
      build_service.perform
      expect(item.reload.position).to eq(4)
    end

    it 'removes assignee when agent is not a member of target pipeline' do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: source_pipeline, user: agent)
      item.update!(assignee: agent)

      build_service.perform
      expect(item.reload.assignee_id).to be_nil
    end

    it 'keeps assignee when agent is a member of target pipeline' do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: source_pipeline, user: agent)
      create(:pipeline_member, pipeline: target_pipeline, user: agent)
      item.update!(assignee: agent)

      build_service.perform
      expect(item.reload.assignee_id).to eq(agent.id)
    end

    it 'keeps assignee when agent is an administrator' do
      admin = create(:user, account: account, role: :administrator)
      item.update_column(:assignee_id, admin.id)
      item.reload

      Current.account = account
      build_service.perform
      Current.reset

      expect(item.reload.assignee_id).to eq(admin.id)
    end

    it 'raises InvalidTargetStageError when stage does not belong to target pipeline' do
      other_stage = create(:pipeline_stage, account: account)
      service = build_service(target_stage_id: other_stage.id)
      expect { service.perform }.to raise_error(Pipelines::ExportItemService::InvalidTargetStageError)
    end

    it 'raises ActiveRecord::RecordInvalid when the contact already has a card in the target pipeline' do
      create(:pipeline_item, pipeline_stage: target_stage, account: account, contact: contact)

      expect { build_service.perform }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'raises SamePipelineError when target pipeline is the same as source pipeline' do
      service = described_class.new(
        pipeline_item: item,
        target_pipeline: source_pipeline,
        target_stage_id: source_stage.id
      )
      expect { service.perform }.to raise_error(Pipelines::ExportItemService::SamePipelineError)
    end
  end
end
