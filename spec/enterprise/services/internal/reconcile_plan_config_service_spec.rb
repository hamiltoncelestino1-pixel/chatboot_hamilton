require 'rails_helper'

RSpec.describe Internal::ReconcilePlanConfigService do
  describe '#perform' do
    let(:service) { described_class.new }

    it 'is a no-op regardless of pricing plan' do
      account = create(:account)
      account.enable_features!('disable_branding', 'audit_logs', 'captain_integration')
      create(:installation_config, name: 'INSTALLATION_NAME', value: 'custom-name')
      create(:installation_config, name: 'LOGO', value: '/custom-path/logo.svg')

      allow(ChatwootHub).to receive(:pricing_plan).and_return('community')
      expect { service.perform }.not_to raise_error

      expect(account.reload.enabled_features.keys).to include('disable_branding', 'audit_logs', 'captain_integration')
      expect(InstallationConfig.find_by(name: 'INSTALLATION_NAME').value).to eq('custom-name')
      expect(InstallationConfig.find_by(name: 'LOGO').value).to eq('/custom-path/logo.svg')
    end

    it 'does not touch the premium config reset warning key' do
      Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING, true)
      service.perform
      expect(Redis::Alfred.get(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)).to eq('true')
    end
  end
end
