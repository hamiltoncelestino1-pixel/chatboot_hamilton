# Task: Destravar `advanced_assignment` globalmente (fim do "modo enterprise/premium")

## Objetivo

A feature de conta `advanced_assignment` (que libera o algoritmo least-busy/"balanced" já
implementado) está hoje `enabled: false, premium: true` em `config/features.yml` — desligada
por padrão, tratada como item pago. Este fork não usa licenciamento real (`premium` só afeta
agrupamento visual no painel Super Admin), então o objetivo é habilitar essa feature **para
todas as contas desta instalação**, sem depender de um Super Admin ligar manualmente.

Esta task **não** mexe em nenhuma lógica de seleção de agente nem em UI — só destrava o acesso
à feature. As tasks `02`/`03` usam essa feature já habilitada; a task `04` constrói a UI em cima
dela.

**Pré-requisito bloqueante**: confirmado com o usuário que esta instalação é single-tenant (só a
conta "Noble Company"). Se isso mudar no futuro (instância passar a hospedar outras contas),
esta task precisa ser revisada antes de reexecutar o padrão de backfill abaixo em qualquer
migration nova — não assumir que continua seguro sem reconfirmar.

---

## Contexto importante

`config/features.yml` (linhas 241-244 atualmente):
```yaml
- name: advanced_assignment
  display_name: Advanced Assignment
  enabled: false
  premium: true
```

`premium: true` é lido só em `app/helpers/super_admin/account_features_helper.rb`
(`account_premium_features`, usado por `partition_features` para separar visualmente "regular"
vs "premium" no painel Super Admin) — **não bloqueia nada tecnicamente** em nenhum controller,
policy ou service. Confirmado por busca: nenhum outro arquivo do projeto usa esse campo.

O mecanismo de feature por conta (`app/models/concerns/featurable.rb`) é um **bitmask**
(`feature_flags`, via gem FlagShihTzu) setado em `before_create :enable_default_features`:
```ruby
def enable_default_features
  config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
  return true if config.blank?
  features_to_enabled = config.value.select { |f| f[:enabled] }.pluck(:name)
  enable_features(*features_to_enabled)
end
```
Ou seja: **não é recalculado dinamicamente** a partir de `config/features.yml` — só lido uma vez
na criação da conta, a partir do valor salvo em `InstallationConfig['ACCOUNT_LEVEL_FEATURE_DEFAULTS']`.

`lib/config_loader.rb#reconcile_feature_config` é o que sincroniza `config/features.yml` →
`InstallationConfig` (roda em todo `db:migrate`/deploy), mas com `reconcile_only_new: true` por
padrão:
```ruby
def compare_and_save_feature(config)
  features = if @reconcile_only_new
               (config.value + account_features).uniq { |h| h['name'] }
             else
               (account_features + config.value).uniq { |h| h['name'] }
             end
  config.update({ name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS', value: features, locked: true })
end
```
`Array#uniq` mantém o **primeiro** elemento de cada nome duplicado — como `config.value` (o que
já está salvo no banco) vem primeiro no array quando `reconcile_only_new: true`, o valor antigo
de `advanced_assignment` (`enabled: false`) **prevalece** mesmo depois de editar
`config/features.yml`. Por isso é preciso uma migration de dados que force a atualização, não
basta editar o YAML.

Dois precedentes reais no repo desse exato padrão:

`db/migrate/20260409091202_enable_assignment_v2_for_new_accounts.rb`:
```ruby
class EnableAssignmentV2ForNewAccounts < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    features = config.value
    feature = features.find { |f| f['name'] == 'assignment_v2' }
    return if feature.blank?

    feature['enabled'] = true
    config.update!(value: features)
    GlobalConfig.clear_cache
  end
end
```

`db/migrate/20260120121402_enable_captain_tasks_for_existing_accounts.rb`:
```ruby
class EnableCaptainTasksForExistingAccounts < ActiveRecord::Migration[7.0]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('captain_tasks') }
    end
  end
end
```

O primeiro cobre **contas novas** (corrige o default salvo em `InstallationConfig`), o segundo
cobre **contas já existentes** (o bitmask já foi setado na criação, precisa de backfill
explícito via `enable_features!`). Esta task combina os dois, porque `advanced_assignment` já
existia com `enabled: false` (mesmo cenário do `assignment_v2`, diferente do `captain_tasks` que
era feature nova).

---

## 1. `config/features.yml`

```diff
 - name: advanced_assignment
   display_name: Advanced Assignment
-  enabled: false
-  premium: true
+  enabled: true
```

Isso garante que instalações **novas** (sem `InstallationConfig` ainda salvo) já nasçam com a
feature ligada via `ConfigLoader#save_as_new_config`.

## 2. Novo arquivo: `db/migrate/<timestamp>_enable_advanced_assignment_globally.rb`

(gerar o timestamp real no momento da implementação, ex. `bin/rails g migration EnableAdvancedAssignmentGlobally` e editar o arquivo gerado)

```ruby
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
```

**Não precisa de `down`** — seguindo o padrão dos dois precedentes citados, nenhum dos dois
implementa rollback (reverter uma feature flag globalmente não é uma operação que faça sentido
desfazer automaticamente).

---

## Verificação

- `bundle exec rails db:migrate` e confirmar no console (`bin/rails console`):
  ```ruby
  Account.find_each { |a| puts "#{a.name}: #{a.feature_enabled?('advanced_assignment')}" }
  # => deve imprimir true para todas as contas existentes
  InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value.find { |f| f['name'] == 'advanced_assignment' }
  # => { 'name' => 'advanced_assignment', 'enabled' => true, ... }
  ```
- Criar uma conta de teste nova (`Account.create!(name: 'Teste')`) e confirmar que ela já nasce
  com `feature_enabled?('advanced_assignment') == true`.
- Conferir no painel Super Admin (`/super_admin/accounts/:id/edit`) que `advanced_assignment`
  não aparece mais separado como "premium" (ou, se o agrupamento visual persistir por cache,
  documentar que é só cosmético).
- Novo spec de migration (ver convenção do projeto para specs de `db/migrate/` — verificar se já
  existe algum spec para `20260409091202`/`20260120121402` como referência de formato antes de
  criar um novo): conta existente sem a feature → depois de rodar `up`, `feature_enabled?('advanced_assignment')`
  é `true`; `InstallationConfig` atualizado; conta criada depois da migration já nasce com a
  feature ligada.
- `pnpm build`/reload do dashboard não é necessário para esta task (é 100% backend) — mas avisar
  que sessões de navegador já abertas não vão ver o reflexo até F5 (feature cacheada no Vuex).
