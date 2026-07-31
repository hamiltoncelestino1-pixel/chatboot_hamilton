require 'rails_helper'
require Rails.root.join('db/migrate/20260731120000_lock_installation_pricing_plan_enterprise')

RSpec.describe LockInstallationPricingPlanEnterprise do
  describe '#up' do
    it 'sets INSTALLATION_PRICING_PLAN to enterprise when the config already exists' do
      InstallationConfig.find_or_create_by(name: 'INSTALLATION_PRICING_PLAN') { |c| c.value = 'community' }

      described_class.new.up

      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').value).to eq('enterprise')
    end

    it 'creates the config when it does not exist yet' do
      InstallationConfig.where(name: 'INSTALLATION_PRICING_PLAN').destroy_all

      expect { described_class.new.up }.not_to raise_error

      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').value).to eq('enterprise')
    end

    it 'reflects immediately through ChatwootHub.pricing_plan' do
      described_class.new.up

      expect(ChatwootHub.pricing_plan).to eq('enterprise')
    end
  end
end
