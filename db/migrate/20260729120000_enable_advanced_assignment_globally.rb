class EnableAdvancedAssignmentGlobally < ActiveRecord::Migration[7.1]
  def up
    update_installation_config_default
    enable_for_existing_accounts
  end

  private

  # Contas novas: ConfigLoader reconcilia com reconcile_only_new=true, então o valor já
  # existente em ACCOUNT_LEVEL_FEATURE_DEFAULTS precisa ser corrigido explicitamente aqui —
  # editar apenas config/features.yml não é suficiente (a feature já existia com enabled: false,
  # ver 20260409091202_enable_assignment_v2_for_new_accounts.rb para o mesmo cenário).
  def update_installation_config_default
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    features = config.value
    feature = features.find { |f| f['name'] == 'advanced_assignment' }
    return if feature.blank?

    feature['enabled'] = true
    config.update!(value: features)
    GlobalConfig.clear_cache
  end

  # Contas existentes: feature_flags é bitmask setado em before_create, não recalculado
  # dinamicamente (ver app/models/concerns/featurable.rb) — precisa de backfill explícito,
  # mesmo padrão de 20260120121402_enable_captain_tasks_for_existing_accounts.rb.
  def enable_for_existing_accounts
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('advanced_assignment') }
    end
  end
end
