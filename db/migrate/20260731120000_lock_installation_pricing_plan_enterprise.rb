class LockInstallationPricingPlanEnterprise < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
    config.value = 'enterprise'
    config.locked = true
    config.save!
  end
end
