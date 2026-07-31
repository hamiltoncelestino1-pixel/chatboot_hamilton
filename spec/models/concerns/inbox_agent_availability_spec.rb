require 'rails_helper'

RSpec.describe InboxAgentAvailability do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:online_user) { create(:user, account: account) }
  let(:offline_user) { create(:user, account: account) }

  before do
    create(:inbox_member, inbox: inbox, user: online_user)
    create(:inbox_member, inbox: inbox, user: offline_user)
  end

  describe '#available_agents' do
    context 'when restrict_to_online_agents is absent/false' do
      it 'returns all inbox members, even offline ones' do
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})

        expect(inbox.available_agents.map(&:user_id)).to contain_exactly(online_user.id, offline_user.id)
      end
    end

    context 'when restrict_to_online_agents is true' do
      before { inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => true }) }

      it 'keeps the old behaviour (online only)' do
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return(online_user.id.to_s => 'online')

        expect(inbox.available_agents.map(&:user_id)).to eq([online_user.id])
      end

      it 'returns an empty relation if nobody is online' do
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})

        expect(inbox.available_agents).to be_empty
      end
    end
  end
end
