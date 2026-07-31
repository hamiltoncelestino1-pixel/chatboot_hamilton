require 'rails_helper'

RSpec.describe AutoAssignment::AgentAssignmentService do
  let!(:account) { create(:account) }
  let!(:inbox) do
    create(:inbox, account: account, enable_auto_assignment: false,
                   auto_assignment_config: { 'restrict_to_online_agents' => true })
  end
  let!(:inbox_members) { create_list(:inbox_member, 5, inbox: inbox) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let!(:online_users) do
    {
      inbox_members[0].user_id.to_s => 'busy',
      inbox_members[1].user_id.to_s => 'busy',
      inbox_members[2].user_id.to_s => 'busy',
      inbox_members[3].user_id.to_s => 'online',
      inbox_members[4].user_id.to_s => 'online'
    }
  end

  before do
    inbox_members.each { |inbox_member| create(:account_user, account: account, user: inbox_member.user) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(online_users)
  end

  describe '#perform' do
    it 'will assign an online agent to the conversation' do
      expect(conversation.reload.assignee).to be_nil
      described_class.new(conversation: conversation, allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).perform
      expect(conversation.reload.assignee).not_to be_nil
    end
  end

  describe '#find_assignee' do
    it 'will return an online agent from the allowed agent ids in roud robin' do
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).find_assignee).to eq(inbox_members[3].user)
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: inbox_members.map(&:user_id).map(&:to_s)).find_assignee).to eq(inbox_members[4].user)
    end

    context 'when restrict_to_online_agents is false/absent' do
      let!(:offline_agent) { create(:user, account: account) }

      before do
        create(:inbox_member, inbox: inbox, user: offline_agent)
        inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => false })
      end

      it 'considers offline agents as eligible' do
        service = described_class.new(conversation: conversation, allowed_agent_ids: [offline_agent.id])
        expect(service.find_assignee).to eq(offline_agent)
      end
    end

    context 'when restrict_to_online_agents is true' do
      let!(:offline_agent) { create(:user, account: account) }

      before { create(:inbox_member, inbox: inbox, user: offline_agent) }

      it 'keeps the online-only filter' do
        service = described_class.new(conversation: conversation, allowed_agent_ids: [offline_agent.id])
        expect(service.find_assignee).to be_nil
      end
    end
  end
end
