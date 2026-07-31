require 'rails_helper'

RSpec.describe Enterprise::AutoAssignment::AssignmentService, type: :service do
  let(:account) { create(:account) }
  let(:assignment_policy) { create(:assignment_policy, account: account, enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent1) { create(:user, account: account, name: 'Agent 1') }
  let(:agent2) { create(:user, account: account, name: 'Agent 2') }
  let(:assignment_service) { AutoAssignment::AssignmentService.new(inbox: inbox) }

  before do
    # Create inbox members
    create(:inbox_member, inbox: inbox, user: agent1)
    create(:inbox_member, inbox: inbox, user: agent2)

    # Link inbox to assignment policy
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: assignment_policy)

    # Enable assignment_v2 (base) and advanced_assignment (premium) features
    account.enable_features('assignment_v2')
    account.save!

    # Set agents as online
    OnlineStatusTracker.update_presence(account.id, 'User', agent1.id)
    OnlineStatusTracker.set_status(account.id, agent1.id, 'online')
    OnlineStatusTracker.update_presence(account.id, 'User', agent2.id)
    OnlineStatusTracker.set_status(account.id, agent2.id, 'online')
  end

  describe '#assignment_mode_balanced?' do
    before do
      account.enable_features('advanced_assignment')
      account.save!
    end

    context 'without a linked AssignmentPolicy' do
      before { inbox.inbox_assignment_policy.destroy }

      it 'uses balanced when auto_assignment_config[assignment_mode] == balanced' do
        inbox.update!(auto_assignment_config: { 'assignment_mode' => 'balanced' })

        expect(assignment_service.send(:assignment_mode_balanced?)).to be true
      end

      it 'uses round robin when assignment_mode is absent' do
        inbox.update!(auto_assignment_config: {})

        expect(assignment_service.send(:assignment_mode_balanced?)).to be false
      end

      it 'uses round robin when assignment_mode is explicitly round_robin' do
        inbox.update!(auto_assignment_config: { 'assignment_mode' => 'round_robin' })

        expect(assignment_service.send(:assignment_mode_balanced?)).to be false
      end

      it 'ignores balanced when advanced_assignment is disabled on the account' do
        account.disable_features!('advanced_assignment')
        inbox.update!(auto_assignment_config: { 'assignment_mode' => 'balanced' })

        expect(assignment_service.send(:assignment_mode_balanced?)).to be false
      end

      it 'assigns to the agent with fewer open conversations when balanced' do
        inbox.update!(auto_assignment_config: { 'assignment_mode' => 'balanced' }, enable_auto_assignment: true)
        create(:conversation, inbox: inbox, assignee: agent1, status: :open)
        conversation = create(:conversation, inbox: inbox, assignee: nil)

        assignment_service.perform_bulk_assignment(limit: 10)

        expect(conversation.reload.assignee).to eq(agent2)
      end
    end

    context 'with a linked AssignmentPolicy' do
      it 'still takes precedence over the inbox direct config' do
        assignment_policy.update!(assignment_order: 'balanced')
        inbox.update!(auto_assignment_config: {})

        expect(assignment_service.send(:assignment_mode_balanced?)).to be true
      end

      it 'assigns to the agent with fewer open conversations via the linked policy' do
        assignment_policy.update!(assignment_order: 'balanced')
        inbox.update!(auto_assignment_config: {}, enable_auto_assignment: true)
        create(:conversation, inbox: inbox, assignee: agent1, status: :open)
        conversation = create(:conversation, inbox: inbox, assignee: nil)

        assignment_service.perform_bulk_assignment(limit: 10)

        expect(conversation.reload.assignee).to eq(agent2)
      end
    end
  end

  describe 'restrict_to_online_agents' do
    let(:offline_agent) { create(:user, account: account, name: 'Offline Agent') }

    before do
      InboxMember.where(inbox: inbox, user: [agent1, agent2]).destroy_all
      create(:inbox_member, inbox: inbox, user: offline_agent)
      inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => false }, enable_auto_assignment: true)
    end

    it 'assigns conversations to an offline inbox member when restrict_to_online_agents is false' do
      conversation = create(:conversation, inbox: inbox, assignee: nil)

      assignment_service.perform_bulk_assignment(limit: 10)

      expect(conversation.reload.assignee).to eq(offline_agent)
    end
  end

  describe 'fallback when rate-limit/capacity filters exclude every candidate' do
    before { inbox.update!(enable_auto_assignment: true) }

    it 'assigns even when every agent is over the fair distribution rate limit' do
      allow(Rails.logger).to receive(:warn).and_call_original
      limit = assignment_policy.fair_distribution_limit
      conversation_id = 0
      [agent1, agent2].each do |agent|
        rate_limiter = AutoAssignment::RateLimiter.new(inbox: inbox, agent: agent)
        limit.times do
          conversation_id += 1
          rate_limiter.track_assignment(instance_double(Conversation, id: conversation_id))
        end
      end
      conversation = create(:conversation, inbox: inbox, assignee: nil)

      assignment_service.perform_bulk_assignment(limit: 1)

      expect(conversation.reload.assignee).to be_present
      expect(Rails.logger).to have_received(:warn).with(
        a_string_matching(/filter=rate_limit .*reason=all_agents_excluded_by_filter action=ignoring_filter_as_last_resort/)
      )
    end

    it 'assigns even when every agent is over the capacity limit' do
      allow(Rails.logger).to receive(:warn).and_call_original
      account.enable_features('advanced_assignment')
      account.save!
      capacity_policy = create(:agent_capacity_policy, account: account)
      create(:inbox_capacity_limit, agent_capacity_policy: capacity_policy, inbox: inbox, conversation_limit: 0)
      [agent1, agent2].each do |agent|
        agent.account_users.find_by(account: account).update!(agent_capacity_policy: capacity_policy)
      end
      conversation = create(:conversation, inbox: inbox, assignee: nil)

      assignment_service.perform_bulk_assignment(limit: 1)

      expect(conversation.reload.assignee).to be_present
      expect(Rails.logger).to have_received(:warn).with(
        a_string_matching(/filter=capacity .*reason=all_agents_excluded_by_filter action=ignoring_filter_as_last_resort/)
      )
    end

    it 'does not fall back for the team boundary (no eligible team members)' do
      team = create(:team, account: account, allow_auto_assign: true)
      conversation = create(:conversation, inbox: inbox, team: team, assignee: nil)

      agent = assignment_service.send(:find_available_agent, conversation)

      expect(agent).to be_nil
    end
  end

  describe 'exclusion rules' do
    let(:capacity_policy) { create(:agent_capacity_policy, account: account) }
    let(:label1) { create(:label, account: account, title: 'high-priority') }
    let(:label2) { create(:label, account: account, title: 'vip') }

    before do
      create(:inbox_capacity_limit, inbox: inbox, agent_capacity_policy: capacity_policy, conversation_limit: 10)
      inbox.enable_auto_assignment = true
      inbox.save!
    end

    context 'when excluding conversations by label' do
      let!(:conversation_with_label) { create(:conversation, inbox: inbox, assignee: nil) }
      let!(:conversation_without_label) { create(:conversation, inbox: inbox, assignee: nil) }

      before do
        conversation_with_label.update_labels([label1.title])

        capacity_policy.update!(exclusion_rules: {
                                  'excluded_labels' => [label1.title]
                                })
      end

      it 'excludes conversations with specified labels' do
        # First check conversations are unassigned
        expect(conversation_with_label.assignee).to be_nil
        expect(conversation_without_label.assignee).to be_nil

        # Run bulk assignment
        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        # Only the conversation without label should be assigned
        expect(assigned_count).to eq(1)
        expect(conversation_with_label.reload.assignee).to be_nil
        expect(conversation_without_label.reload.assignee).to be_present
      end

      it 'handles bulk assignment correctly' do
        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        # Only 1 conversation should be assigned (the one without label)
        expect(assigned_count).to eq(1)
        expect(conversation_with_label.reload.assignee).to be_nil
        expect(conversation_without_label.reload.assignee).to be_present
      end

      it 'excludes conversations with multiple labels' do
        conversation_without_label.update_labels([label2.title])

        capacity_policy.update!(exclusion_rules: {
                                  'excluded_labels' => [label1.title, label2.title]
                                })

        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        # Both conversations should be excluded
        expect(assigned_count).to eq(0)
        expect(conversation_with_label.reload.assignee).to be_nil
        expect(conversation_without_label.reload.assignee).to be_nil
      end
    end

    context 'when excluding conversations by age' do
      let!(:old_conversation) { create(:conversation, inbox: inbox, assignee: nil, created_at: 25.hours.ago) }
      let!(:recent_conversation) { create(:conversation, inbox: inbox, assignee: nil, created_at: 1.hour.ago) }

      before do
        capacity_policy.update!(exclusion_rules: {
                                  'exclude_older_than_hours' => 24
                                })
      end

      it 'excludes conversations older than specified hours' do
        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        # Only recent conversation should be assigned
        expect(assigned_count).to eq(1)
        expect(old_conversation.reload.assignee).to be_nil
        expect(recent_conversation.reload.assignee).to be_present
      end

      it 'handles different time thresholds' do
        capacity_policy.update!(exclusion_rules: {
                                  'exclude_older_than_hours' => 2
                                })

        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        # Only conversation created within 2 hours should be assigned
        expect(assigned_count).to eq(1)
        expect(recent_conversation.reload.assignee).to be_present
      end
    end

    context 'when combining exclusion rules' do
      it 'applies both exclusion rules' do
        # Create conversations
        old_conversation_with_label = create(:conversation, inbox: inbox, assignee: nil, created_at: 25.hours.ago)
        old_conversation_without_label = create(:conversation, inbox: inbox, assignee: nil, created_at: 25.hours.ago)
        recent_conversation_with_label = create(:conversation, inbox: inbox, assignee: nil, created_at: 1.hour.ago)
        recent_conversation_without_label = create(:conversation, inbox: inbox, assignee: nil, created_at: 1.hour.ago)

        # Add labels
        old_conversation_with_label.update_labels([label1.title])
        recent_conversation_with_label.update_labels([label1.title])

        capacity_policy.update!(exclusion_rules: {
                                  'excluded_labels' => [label1.title],
                                  'exclude_older_than_hours' => 24
                                })

        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        # Only recent conversation without label should be assigned
        expect(assigned_count).to eq(1)
        expect(old_conversation_with_label.reload.assignee).to be_nil
        expect(old_conversation_without_label.reload.assignee).to be_nil
        expect(recent_conversation_with_label.reload.assignee).to be_nil
        expect(recent_conversation_without_label.reload.assignee).to be_present
      end
    end

    context 'when exclusion rules are empty' do
      let!(:conversation1) { create(:conversation, inbox: inbox, assignee: nil) }
      let!(:conversation2) { create(:conversation, inbox: inbox, assignee: nil) }

      before do
        capacity_policy.update!(exclusion_rules: {})
      end

      it 'assigns all eligible conversations' do
        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        expect(assigned_count).to eq(2)
        expect(conversation1.reload.assignee).to be_present
        expect(conversation2.reload.assignee).to be_present
      end
    end

    context 'when no capacity policy exists' do
      let!(:conversation1) { create(:conversation, inbox: inbox, assignee: nil) }
      let!(:conversation2) { create(:conversation, inbox: inbox, assignee: nil) }

      before do
        InboxCapacityLimit.destroy_all
      end

      it 'assigns all eligible conversations without exclusions' do
        assigned_count = assignment_service.perform_bulk_assignment(limit: 10)

        expect(assigned_count).to eq(2)
        expect(conversation1.reload.assignee).to be_present
        expect(conversation2.reload.assignee).to be_present
      end
    end
  end
end
