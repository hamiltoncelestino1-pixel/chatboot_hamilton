# Task: Fixar `INSTALLATION_PRICING_PLAN` permanentemente em `'enterprise'`

## Objetivo

Setar `InstallationConfig['INSTALLATION_PRICING_PLAN']` pra `'enterprise'` de forma permanente,
via migration de dados. Camada 2 das 3 de defesa em profundidade — ver `00-visao-geral.md`.

Com o ping desligado (task `01`), esse valor nunca mais seria atualizado de qualquer forma — mas
fixá-lo explicitamente garante que, mesmo que o cron volte por engano no futuro (ex. numa
sincronização com o upstream do Chatwoot), `Internal::ReconcilePlanConfigService#perform` já
teria um `return` antecipado (`return if ChatwootHub.pricing_plan != 'community'`), sem depender
só da task `01` ou `03` pra ficar seguro.

**Efeito colateral positivo, não um bug**: esse mesmo valor também é lido como sinal de
"instalação licenciada" em outros 4 lugares do código (fora do mecanismo de reset) — todos ficam
mais permissivos/corretos com `'enterprise'`. Ver seção de contexto.

---

## Contexto importante

`lib/chatwoot_hub.rb`:
```ruby
def self.pricing_plan
  return 'community' unless ChatwootApp.enterprise?
  InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')&.value || 'community'
end
```

`config/installation_config.yml` (linhas 283-288) — valores atuais (nunca alterados nesta
instalação):
```yaml
- name: INSTALLATION_PRICING_PLAN
  value: 'community'
  description: 'The pricing plan for the installation, retrieved from the billing API'
- name: INSTALLATION_PRICING_PLAN_QUANTITY
  value: 0
  description: 'The number of licenses purchased for the installation, retrieved from the billing API'
```

**Por que `'enterprise'` e não `'premium'` (decisão crítica, já validada)**:
`enterprise/app/models/enterprise/concerns/user.rb`:
```ruby
def ensure_installation_pricing_plan_quantity
  return unless ChatwootHub.pricing_plan == 'premium'
  errors.add(:base, '...') if User.count >= ChatwootHub.pricing_plan_quantity
end
```
`INSTALLATION_PRICING_PLAN_QUANTITY` tem default `0` e esta task não mexe nele — se o plano fosse
`'premium'`, **toda criação de usuário novo passaria a falhar** (`User.count >= 0` é sempre
verdadeiro). `'enterprise'` evita esse branch inteiro por completo.

`'enterprise'` também é literalmente o valor que `lib/chatwoot_app.rb#self_hosted_enterprise?` já
espera pra este cenário de instalação self-hosted (usado por
`enterprise/app/models/enterprise/account.rb` e o serviço de sync do Captain) — não é um valor
inventado, é o idioma já usado no projeto pra "self-hosted com tudo liberado".

**Outros lugares que leem esse valor** (todos ficam mais permissivos, nenhum quebra):
- `enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb` — libera seções
  extras (`custom_branding`, `internal`, `captain`, `saml`) no painel Super Admin.
- `enterprise/app/views/fields/account_features_field/_form.html.erb` — checkboxes de feature
  deixam de vir desabilitados por padrão na tela de edição de conta do Super Admin.
- `app/controllers/dashboard_controller.rb#allowed_login_methods` — libera a opção de login SAML
  (`methods << 'saml' if ChatwootHub.pricing_plan != 'community' && ...`).
- `app/helpers/super_admin/features.yml` — cosmético, mostra `custom_branding`/`agent_capacity`/
  `audit_logs`/`disable_branding` como já habilitados no painel Super Admin > Features.

Padrão de migration já usado no ciclo anterior pra `InstallationConfig` (referência de estilo),
`db/migrate/20260729120000_enable_advanced_assignment_globally.rb`.

---

## 1. Novo arquivo: `db/migrate/<timestamp>_lock_installation_pricing_plan_enterprise.rb`

(gerar o timestamp real no momento da implementação, ex.
`bin/rails g migration LockInstallationPricingPlanEnterprise`)

```ruby
class LockInstallationPricingPlanEnterprise < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
    config.value = 'enterprise'
    config.locked = true
    config.save!
  end
end
```

**Sem `down`** — mesmo padrão da migration de referência (reverter uma config de licenciamento
globalmente não é uma operação que faça sentido desfazer automaticamente).

`locked: true` mantém o comportamento já default desse registro (`# locked :boolean default(TRUE)`
em `app/models/installation_config.rb`) — só controla se aparece como editável na tela de Super
Admin (`scope :editable, -> { where(locked: false) }`), não afeta a capacidade desta migration
(ou de qualquer código Ruby) de escrever o valor via ActiveRecord diretamente.

**Confirmado que a ordem não importa em relação às outras tasks**: `lib/config_loader.rb#reconcile_feature_config`/`save_general_config`
roda com `reconcile_only_new: true` (default, chamado depois de todo `db:migrate` via
`lib/tasks/db_enhancements.rake`) — só cria configs que **não existem**, nunca sobrescreve um
`InstallationConfig` já existente de volta pro valor default do YAML. Como
`INSTALLATION_PRICING_PLAN` já existe (`config/installation_config.yml` o declara), essa
migration pode rodar antes, depois ou no mesmo `db:migrate` que outras mudanças, sem risco de ser
revertida por esse hook automático.

---

## Verificação

- `bundle exec rails db:migrate` e no `bin/rails console`:
  ```ruby
  ChatwootHub.pricing_plan # => "enterprise"
  ChatwootApp.self_hosted_enterprise? # => true
  ```
- Novo spec de migration, seguindo o padrão de
  `spec/db/migrate/20260729120000_enable_advanced_assignment_globally_spec.rb`:
  ```ruby
  require Rails.root.join('db/migrate/<timestamp>_lock_installation_pricing_plan_enterprise')

  RSpec.describe LockInstallationPricingPlanEnterprise do
    it 'sets INSTALLATION_PRICING_PLAN to enterprise' do
      InstallationConfig.find_or_create_by(name: 'INSTALLATION_PRICING_PLAN') { |c| c.value = 'community' }
      described_class.new.up
      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').value).to eq('enterprise')
    end

    it 'works even if the config does not exist yet' do
      InstallationConfig.where(name: 'INSTALLATION_PRICING_PLAN').destroy_all
      expect { described_class.new.up }.not_to raise_error
      expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN').value).to eq('enterprise')
    end
  end
  ```
- Confirmar manualmente que criar um usuário novo continua funcionando normalmente após a
  migration (regressão direta do risco de usar `'premium'` por engano — mesmo não sendo esse o
  valor escolhido, vale o teste de sanidade).
- Conferir no Super Admin > App Configs se as seções extras (`custom_branding`, `saml`, etc.)
  aparecem — comportamento esperado, não é bug.
- `bundle exec rubocop` limpo.
