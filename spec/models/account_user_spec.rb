# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountUser do
  include ActiveJob::TestHelper

  let!(:account_user) { create(:account_user) }
  let!(:inbox) { create(:inbox, account: account_user.account) }

  describe 'notification_settings' do
    it 'gets created with the right default settings' do
      expect(account_user.user.notification_settings).not_to be_nil

      expect(account_user.user.notification_settings.first.email_conversation_creation?).to be(false)
      expect(account_user.user.notification_settings.first.email_conversation_assignment?).to be(true)
    end
  end

  describe 'permissions' do
    it 'returns the right permissions' do
      expect(account_user.permissions).to eq(['agent'])
    end

    it 'returns the right permissions for administrator' do
      account_user.administrator!
      expect(account_user.permissions).to eq(['administrator'])
    end
  end

  describe 'availability_status' do
    let(:agent_account_user) { create(:account_user, role: :agent) }
    let(:admin_account_user) { create(:account_user, role: :administrator) }

    context 'when auto_offline is enabled' do
      it 'coerces a connected agent with offline status to online' do
        allow(agent_account_user).to receive(:online_presence?).and_return(true)
        allow(OnlineStatusTracker).to receive(:get_status).and_return('offline')
        expect(agent_account_user.availability_status).to eq('online')
      end

      it 'returns offline for a disconnected agent' do
        allow(agent_account_user).to receive(:online_presence?).and_return(false)
        expect(agent_account_user.availability_status).to eq('offline')
      end

      it 'keeps a connected administrator offline' do
        allow(admin_account_user).to receive(:online_presence?).and_return(true)
        allow(OnlineStatusTracker).to receive(:get_status).and_return('offline')
        expect(admin_account_user.availability_status).to eq('offline')
      end
    end

    context 'when auto_offline is disabled' do
      it 'coerces a connected agent stored as offline to online' do
        agent_account_user.update!(auto_offline: false, availability: 'offline')
        allow(agent_account_user).to receive(:online_presence?).and_return(true)
        expect(agent_account_user.availability_status).to eq('online')
      end

      it 'keeps a connected administrator offline' do
        admin_account_user.update!(auto_offline: false, availability: 'offline')
        allow(admin_account_user).to receive(:online_presence?).and_return(true)
        expect(admin_account_user.availability_status).to eq('offline')
      end
    end
  end

  describe 'destroy call agent::destroy service' do
    it 'gets created with the right default settings' do
      create(:conversation, account: account_user.account, assignee: account_user.user, inbox: inbox)
      user = account_user.user

      expect(user.assigned_conversations.count).to eq(1)

      perform_enqueued_jobs do
        account_user.destroy!
      end

      expect(user.assigned_conversations.count).to eq(0)
    end
  end
end
