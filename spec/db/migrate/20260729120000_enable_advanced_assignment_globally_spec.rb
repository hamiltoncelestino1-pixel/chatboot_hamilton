# This is the only spec/ directory in the project that mirrors `db/` instead of an
# autoloaded root (spec/models <-> app/models, spec/services <-> app/services, etc.) —
# db/migrate isn't in Rails' autoload/eager-load path, hence the manual `require` below.
# Chosen because neither precedent migration this one is modeled after
# (20260409091202_enable_assignment_v2_for_new_accounts,
# 20260120121402_enable_captain_tasks_for_existing_accounts) has an automated spec, only
# manual `bin/rails console` verification — so there was no existing pattern to follow.
# If more migration specs are added later, watch for class name collisions across the
# suite: a `require`d migration file defines a plain top-level constant, not an
# autoloaded/reloadable one, so reusing the same class name in another spec file loaded
# in the same run raises `TypeError: superclass mismatch`.
require 'rails_helper'
require Rails.root.join('db/migrate/20260729120000_enable_advanced_assignment_globally.rb')

RSpec.describe EnableAdvancedAssignmentGlobally do
  describe '#up' do
    let!(:account) { create(:account) }

    context 'when ACCOUNT_LEVEL_FEATURE_DEFAULTS exists with advanced_assignment disabled' do
      let!(:installation_config) do
        create(:installation_config, name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS', value: [
                 { 'name' => 'assignment_v2', 'enabled' => true },
                 { 'name' => 'advanced_assignment', 'enabled' => false }
               ])
      end

      it 'enables advanced_assignment for existing accounts' do
        expect(account.feature_enabled?('advanced_assignment')).to be false

        described_class.new.up

        expect(account.reload.feature_enabled?('advanced_assignment')).to be true
      end

      it 'flips advanced_assignment to enabled in ACCOUNT_LEVEL_FEATURE_DEFAULTS' do
        described_class.new.up

        feature = installation_config.reload.value.find { |f| f['name'] == 'advanced_assignment' }
        expect(feature['enabled']).to be true
      end

      it 'leaves other features in ACCOUNT_LEVEL_FEATURE_DEFAULTS untouched' do
        described_class.new.up

        feature = installation_config.reload.value.find { |f| f['name'] == 'assignment_v2' }
        expect(feature['enabled']).to be true
      end

      it 'makes accounts created after the migration inherit advanced_assignment enabled' do
        described_class.new.up

        new_account = create(:account)
        expect(new_account.feature_enabled?('advanced_assignment')).to be true
      end
    end

    context 'when ACCOUNT_LEVEL_FEATURE_DEFAULTS does not have an advanced_assignment entry' do
      let!(:installation_config) do
        create(:installation_config, name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS', value: [
                 { 'name' => 'assignment_v2', 'enabled' => true }
               ])
      end

      it 'still enables the feature for existing accounts without raising' do
        expect { described_class.new.up }.not_to raise_error
        expect(account.reload.feature_enabled?('advanced_assignment')).to be true
      end

      it 'does not add a new entry to ACCOUNT_LEVEL_FEATURE_DEFAULTS' do
        described_class.new.up

        names = installation_config.reload.value.pluck('name')
        expect(names).to eq(['assignment_v2'])
      end
    end

    context 'when ACCOUNT_LEVEL_FEATURE_DEFAULTS does not exist yet' do
      it 'still enables the feature for existing accounts without raising' do
        expect { described_class.new.up }.not_to raise_error
        expect(account.reload.feature_enabled?('advanced_assignment')).to be true
      end
    end
  end
end
