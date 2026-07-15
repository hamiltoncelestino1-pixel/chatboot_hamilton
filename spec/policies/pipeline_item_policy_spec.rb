# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PipelineItemPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }

  let(:admin_context) { { user: admin, account: account, account_user: admin.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  before { pipeline.add_members([agent.id, other_agent.id]) }

  let!(:item_owned_by_agent) { create(:pipeline_item, pipeline_stage: stage, account: account, assignee: agent) }
  let!(:item_owned_by_other) { create(:pipeline_item, pipeline_stage: stage, account: account, assignee: other_agent) }
  let!(:item_unassigned) { create(:pipeline_item, pipeline_stage: stage, account: account) }

  describe 'Scope#resolve' do
    context 'when user is an agent' do
      subject { described_class::Scope.new(agent_context, PipelineItem.all).resolve }

      it 'returns all items including those owned by other agents' do
        expect(subject).to include(item_owned_by_agent, item_owned_by_other, item_unassigned)
      end
    end

    context 'when user is an administrator' do
      subject { described_class::Scope.new(admin_context, PipelineItem.all).resolve }

      it 'returns all items' do
        expect(subject).to include(item_owned_by_agent, item_owned_by_other, item_unassigned)
      end
    end
  end

  permissions :destroy? do
    context 'when user is an agent' do
      it 'denies destroy' do
        expect(subject).not_to permit(agent_context, item_owned_by_agent)
      end
    end

    context 'when user is an administrator' do
      it 'allows destroy' do
        expect(subject).to permit(admin_context, item_owned_by_agent)
      end
    end
  end

  permissions :index?, :show?, :create?, :update?, :reorder?, :export? do
    it 'allows agents' do
      expect(subject).to permit(agent_context, item_owned_by_agent)
    end

    it 'allows administrators' do
      expect(subject).to permit(admin_context, item_owned_by_agent)
    end
  end
end
