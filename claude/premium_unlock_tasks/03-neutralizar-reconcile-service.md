# Task: Neutralizar `Internal::ReconcilePlanConfigService`

## Objetivo

Transformar `Internal::ReconcilePlanConfigService#perform` num no-op documentado. Camada 3 das 3
de defesa em profundidade — ver `00-visao-geral.md`. Mesmo que as tasks `01` (cron) e `02`
(pricing plan) revertam por algum motivo no futuro (ex. merge com upstream do Chatwoot), esta
classe nunca mais faz nada destrutivo.

---

## Contexto importante

Implementação atual completa, `enterprise/app/services/internal/reconcile_plan_config_service.rb`:
```ruby
class Internal::ReconcilePlanConfigService
  def perform
    remove_premium_config_reset_warning
    return if ChatwootHub.pricing_plan != 'community'

    create_premium_config_reset_warning if premium_config_reset_required?

    reconcile_premium_config
    reconcile_premium_features
  end

  private

  def config_path
    @config_path ||= Rails.root.join('enterprise/config')
  end

  def premium_config
    @premium_config ||= YAML.safe_load(File.read("#{config_path}/premium_installation_config.yml")).freeze
  end

  def remove_premium_config_reset_warning
    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
  end

  def create_premium_config_reset_warning
    Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING, true)
  end

  def premium_config_reset_required?
    premium_config.any? do |config|
      config = config.with_indifferent_access
      existing_config = InstallationConfig.find_by(name: config[:name])
      existing_config&.value != config[:value] if existing_config.present?
    end
  end

  def reconcile_premium_config
    premium_config.each do |config|
      new_config = config.with_indifferent_access
      existing_config = InstallationConfig.find_by(name: new_config[:name])
      next if existing_config&.value == new_config[:value]

      existing_config&.update!(value: new_config[:value])
    end
  end

  def premium_features
    @premium_features ||= YAML.safe_load(File.read("#{config_path}/premium_features.yml")).freeze
  end

  def reconcile_premium_features
    Account.find_in_batches do |accounts|
      accounts.each do |account|
        account.disable_features!(*premium_features)
      end
    end
  end
end
```

Único ponto de chamada em todo o código de produção (confirmado por busca):
`enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb`:
```ruby
def reconcile_premium_config_and_features
  Internal::ReconcilePlanConfigService.new.perform
end
```
Esse arquivo **não precisa ser alterado** por esta task — continua chamando `.new.perform`
normalmente, só que agora `perform` não faz nada.

`spec/enterprise/jobs/enterprise/internal/check_new_versions_job_spec.rb` já mocka esse serviço
via `instance_double(Internal::ReconcilePlanConfigService)` — é opaco à mudança interna, **não
precisa ser tocado** por esta task.

---

## 1. `enterprise/app/services/internal/reconcile_plan_config_service.rb`

Substituir o arquivo inteiro:

```ruby
# Este fork não aplica o modelo de licenciamento comercial do Chatwoot — toda conta tem acesso
# total ao que seria "premium" (ver config/features.yml e migrations como
# LockInstallationPricingPlanEnterprise / EnableAdvancedAssignmentGlobally).
#
# Este serviço historicamente desligava features premium (enterprise/config/premium_features.yml)
# e resetava configs de branding — INSTALLATION_NAME/LOGO/BRAND_NAME/etc.
# (enterprise/config/premium_installation_config.yml) — toda madrugada em produção, sempre que o
# plano reportado pelo hub da Chatwoot (INSTALLATION_PRICING_PLAN) fosse 'community', que era o
# valor default nunca alterado nesta instalação. Isso desfazia customizações reais (ex. o rebrand
# da Noble) e qualquer feature destravada globalmente, de forma silenciosa.
#
# Neutralizado de propósito — ver claude/premium_unlock_tasks/00-visao-geral.md para o plano
# completo (3 camadas de defesa). Não reativar sem uma decisão de produto explícita de
# reintroduzir licenciamento real.
class Internal::ReconcilePlanConfigService
  def perform
    # no-op by design
  end
end
```

## 2. Reescrever `spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb`

O arquivo atual tem ~8 exemplos testando o comportamento destrutivo antigo (contexto "community"
vs "not community" — ver o arquivo atual antes de sobrescrever, pra entender o que estava sendo
coberto). Substituir por:

```ruby
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
```

Confirmar se as factories `:account` e `:installation_config` usadas acima já existem no projeto
(o spec antigo já as usava, então devem existir) antes de assumir a sintaxe exata.

---

## Verificação

- `bundle exec rspec spec/enterprise/services/internal/reconcile_plan_config_service_spec.rb`
- `bundle exec rspec spec/enterprise/jobs/enterprise/internal/check_new_versions_job_spec.rb` —
  deve continuar passando sem nenhuma alteração no arquivo (só confirma que o mock ainda bate).
- Manual: `bin/rails console`,
  ```ruby
  account = Account.first
  account.enable_features!('disable_branding')
  Internal::ReconcilePlanConfigService.new.perform
  account.reload.feature_enabled?('disable_branding') # => deve continuar true
  ```
- Confirmar que `InstallationConfig` de branding (ex. `BRAND_NAME`) não muda de valor depois de
  chamar `perform` manualmente, mesmo simulando `pricing_plan == 'community'`.
- `bundle exec rubocop` limpo.
