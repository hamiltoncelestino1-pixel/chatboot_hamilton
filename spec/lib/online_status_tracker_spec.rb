require 'rails_helper'

describe OnlineStatusTracker do
  let!(:account) { create(:account) }
  let!(:user1) { create(:user, account: account) }
  let!(:user2) { create(:user, account: account) }
  let!(:user3) { create(:user, account: account) }

  context 'when get_available_users' do
    before do
      described_class.update_presence(account.id, 'User', user1.id)
      described_class.update_presence(account.id, 'User', user2.id)
    end

    it 'returns only the online user ids with presence' do
      expect(described_class.get_available_users(account.id).keys).to contain_exactly(user1.id.to_s, user2.id.to_s)
      expect(described_class.get_available_users(account.id).values).not_to include(user3.id)
    end

    it 'returns agents who have auto offline configured false' do
      user2.account_users.first.update(auto_offline: false)
      expect(described_class.get_available_users(account.id).keys).to contain_exactly(user1.id.to_s, user2.id.to_s)
    end

    it 'returns the availability from the db if it is not present in redis and set it in redis' do
      # user2 needs to be an administrator, otherwise the offline status is coerced to online while connected
      user2.account_users.find_by(account_id: account.id).update!(role: :administrator, availability: 'offline')
      # clear the redis cache to ensure values are fetched from db
      Redis::Alfred.delete(format(Redis::Alfred::ONLINE_STATUS, account_id: account.id))
      expect(described_class.get_available_users(account.id)[user1.id.to_s]).to eq('online')
      expect(described_class.get_available_users(account.id)[user2.id.to_s]).to eq('offline')
      # ensure online status is also set
      expect(Redis::Alfred.hmget(format(Redis::Alfred::ONLINE_STATUS, account_id: account.id),
                                 [user1.id.to_s, user2.id.to_s])).to eq(%w[online offline])
    end

    it 'coerces a connected non-admin (agent) with offline status to online' do
      user2.account_users.find_by(account_id: account.id).update!(availability: 'offline')
      expect(described_class.get_available_users(account.id)[user2.id.to_s]).to eq('online')
    end

    it 'keeps an administrator offline even while connected' do
      user2.account_users.find_by(account_id: account.id).update!(role: :administrator, availability: 'offline')
      expect(described_class.get_available_users(account.id)[user2.id.to_s]).to eq('offline')
    end

    it 'does not coerce a disconnected agent with auto_offline false' do
      # user3 has no presence; auto_offline false keeps it in the available users list
      user3.account_users.find_by(account_id: account.id).update!(auto_offline: false, availability: 'offline')
      expect(described_class.get_available_users(account.id)[user3.id.to_s]).to eq('offline')
    end
  end

  context 'when get_available_contacts' do
    let(:online_contact) { create(:contact, account: account) }
    let(:offline_contact) { create(:contact, account: account) }

    before do
      described_class.update_presence(account.id, 'Contact', online_contact.id)
      # creating a stale record for offline contact presence
      Redis::Alfred.zadd(format(Redis::Alfred::ONLINE_PRESENCE_CONTACTS, account_id: account.id),
                         (Time.zone.now - (OnlineStatusTracker::CONTACT_PRESENCE_DURATION + 20)).to_i, offline_contact.id)
    end

    it 'returns only the online contact ids with presence' do
      expect(described_class.get_available_contacts(account.id).keys).to contain_exactly(online_contact.id.to_s)
    end

    it 'flushes the stale records from sorted set after the duration' do
      described_class.get_available_contacts(account.id)
      expect(Redis::Alfred.zscore(format(Redis::Alfred::ONLINE_PRESENCE_CONTACTS, account_id: account.id), offline_contact.id)).to be_nil
    end
  end
end
