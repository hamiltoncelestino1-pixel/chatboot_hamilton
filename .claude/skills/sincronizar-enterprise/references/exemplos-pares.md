# Código de referência — mecanismo enterprise e pares core/extensão

Todo o código abaixo foi lido verbatim do repositório nesta sessão.

## O mecanismo de injeção — `config/initializers/01_inject_enterprise_edition_module.rb`

```ruby
# frozen_string_literal: true

# original Authors: Gitlab
# https://gitlab.com/gitlab-org/gitlab/-/blob/master/config/initializers/0_inject_enterprise_edition_module.rb
#

### Ref: https://medium.com/@leo_hetsch/ruby-modules-include-vs-prepend-vs-extend-f09837a5b073
# Ancestors chain : it holds a list of constant names which are its ancestors
#  example, by calling ancestors on the String class,
#  String.ancestors => [String, Comparable, Object, PP::ObjectMixin, Kernel, BasicObject]
#
# Include: Ruby will insert the module into the ancestors chain of the class, just after its superclass
# ancestor chain : [OriginalClass, IncludedModule, ...]
#
# Extend: class will actually import the module methods as class methods
#
# Prepend: Ruby will look into the module methods before looking into the class.
# ancestor chain : [PrependedModule, OriginalClass, ...]
########

require 'active_support/inflector'

module InjectEnterpriseEditionModule
  def prepend_mod_with(constant_name, namespace: Object, with_descendants: false)
    each_extension_for(constant_name, namespace) do |constant|
      prepend_module(constant, with_descendants)
    end
  end

  def extend_mod_with(constant_name, namespace: Object)
    each_extension_for(
      constant_name,
      namespace,
      &method(:extend)
    )
  end

  def include_mod_with(constant_name, namespace: Object)
    each_extension_for(
      constant_name,
      namespace,
      &method(:include)
    )
  end

  def prepend_mod(with_descendants: false)
    prepend_mod_with(name, with_descendants: with_descendants)
  end

  def extend_mod
    extend_mod_with(name)
  end

  def include_mod
    include_mod_with(name)
  end

  private

  def prepend_module(mod, with_descendants)
    prepend(mod)

    descendants.each { |descendant| descendant.prepend(mod) } if with_descendants
  end

  def each_extension_for(constant_name, namespace)
    ChatwootApp.extensions.each do |extension_name|
      extension_namespace =
        const_get_maybe_false(namespace, extension_name.camelize)

      extension_module =
        const_get_maybe_false(extension_namespace, constant_name)

      yield(extension_module) if extension_module
    end
  end

  def const_get_maybe_false(mod, name)
    mod&.const_defined?(name, false) && mod&.const_get(name, false)
  end
end

Module.prepend(InjectEnterpriseEditionModule)
```

A última linha (`Module.prepend(InjectEnterpriseEditionModule)`) é o que torna
`prepend_mod_with`/`include_mod_with`/`extend_mod_with` chamáveis como métodos de classe em
**qualquer** classe/módulo do projeto.

## `ChatwootApp.extensions` — `lib/chatwoot_app.rb` (linhas 36-44)

```ruby
def self.extensions
  if custom?
    %w[enterprise custom]
  elsif enterprise?
    %w[enterprise]
  else
    %w[]
  end
end
```

Numa instalação normal (não `custom?`), retorna `['enterprise']` — só essa namespace é
verificada.

## Resolução do constante, passo a passo (para `Account.prepend_mod_with('Account')`)

1. `ChatwootApp.extensions` → `['enterprise']`.
2. Para `extension_name = 'enterprise'`: `extension_namespace =
   const_get_maybe_false(Object, 'Enterprise')` → resolve o módulo top-level `Enterprise`
   (autoloaded via Zeitwerk a partir das raízes `enterprise/app/**`).
3. `extension_module = const_get_maybe_false(Enterprise, 'Account')` → resolve
   `Enterprise::Account`.
4. Se o constante existir, `prepend_module` roda: `Account.prepend(Enterprise::Account)`.

Ou seja: **não é uma busca de arquivo direta, é resolução de constante Ruby** — o path do
arquivo é consequência da convenção de nomenclatura do Zeitwerk para as raízes de autoload
`enterprise/app/**`.

## Autoload/eager_load — `config/application.rb` (linhas 42-53)

```ruby
config.eager_load_paths << Rails.root.join('lib')
config.eager_load_paths << Rails.root.join('enterprise/lib')
config.eager_load_paths << Rails.root.join('enterprise/listeners')
# rubocop:disable Rails/FilePath
config.eager_load_paths += Dir["#{Rails.root}/enterprise/app/**"]
# rubocop:enable Rails/FilePath
# Add enterprise views to the view paths
config.paths['app/views'].unshift('enterprise/app/views')

# Load enterprise initializers alongside standard initializers
enterprise_initializers = Rails.root.join('enterprise/config/initializers')
Dir[enterprise_initializers.join('**/*.rb')].each { |f| require f } if enterprise_initializers.exist?
```

A linha-chave é `config.eager_load_paths += Dir["#{Rails.root}/enterprise/app/**"]` — isso
adiciona **cada subpasta** de `enterprise/app/` (`enterprise/app/models`,
`enterprise/app/models/enterprise`, `enterprise/app/services`, etc.) como sua própria raiz de
autoload Zeitwerk. É por isso que `enterprise/app/models/enterprise/account.rb` (raiz =
`enterprise/app/models`, resto do path = `enterprise/account.rb`) mapeia exatamente pro
constante `Enterprise::Account` — e não `Enterprise::App::Models::Enterprise::Account`.

## 4 pares completos (core + extensão), confirmados lendo os dois lados

### Model — `Account` ↔ `Enterprise::Account`

`app/models/account.rb` (linhas 210-216, logo após o `end` que fecha a classe):
```ruby
end

Account.prepend_mod_with('Account')
Account.prepend_mod_with('Account::PlanUsageAndLimits')
Account.include_mod_with('Concerns::Account')
Account.include_mod_with('Audit::Account')
```

`enterprise/app/models/enterprise/account.rb` (trechos):
```ruby
module Enterprise::Account
  class << self
    def captain_document_sync_intervals
      parse_captain_document_sync_intervals(InstallationConfig.find_by(name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS')&.value)
      # ...
    end
  end

  def manually_managed_features; end

  # ...

  def saml_enabled?
    saml_settings&.saml_enabled? || false
  end

  # ...
end
```

As outras 3 chamadas do `Account` mapeiam pra:
- `Account.prepend_mod_with('Account::PlanUsageAndLimits')` →
  `enterprise/app/models/enterprise/account/plan_usage_and_limits.rb`,
  `module Enterprise::Account::PlanUsageAndLimits`
- `Account.include_mod_with('Concerns::Account')` →
  `enterprise/app/models/enterprise/concerns/account.rb`,
  `module Enterprise::Concerns::Account` (`extend ActiveSupport::Concern`, `included do
  store_accessor :settings, :conversation_required_attributes end`)
- `Account.include_mod_with('Audit::Account')` →
  `enterprise/app/models/enterprise/audit/account.rb`,
  `module Enterprise::Audit::Account` (`extend ActiveSupport::Concern`, `included do audited
  except: :updated_at, on: [:update]; has_associated_audits end`)

### Policy — `ReportPolicy` ↔ `Enterprise::ReportPolicy`

`app/policies/report_policy.rb` (completo):
```ruby
class ReportPolicy < ApplicationPolicy
  def view?
    @account_user.administrator?
  end
end

ReportPolicy.prepend_mod_with('ReportPolicy')
```

`enterprise/app/policies/enterprise/report_policy.rb` (completo):
```ruby
module Enterprise::ReportPolicy
  def view?
    @account_user.custom_role&.permissions&.include?('report_manage') || super
  end
end
```

Exemplo claro do padrão `prepend` + `super`: a extensão roda primeiro, e só cai pro core
(`super`) se a condição dela não bater.

### Service — `Conversations::PermissionFilterService` ↔ extensão

`app/services/conversations/permission_filter_service.rb` (linha 40):
```ruby
Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
```

`enterprise/app/services/enterprise/conversations/permission_filter_service.rb` (linha 1 +
trecho):
```ruby
module Enterprise::Conversations::PermissionFilterService
  def perform
    return filter_by_permissions(permissions) if user_has_custom_role?

    super
  end
  # ...
end
```

### Controller — `Api::V1::Accounts::AgentsController` ↔ extensão

`app/controllers/api/v1/accounts/agents_controller.rb` (linhas 111-113, fim do arquivo):
```ruby
end

Api::V1::Accounts::AgentsController.prepend_mod_with('Api::V1::Accounts::AgentsController')
```

`enterprise/app/controllers/enterprise/api/v1/accounts/agents_controller.rb` (completo):
```ruby
module Enterprise::Api::V1::Accounts::AgentsController
  def create
    super
    associate_agent_with_custom_role
  end

  def update
    super
    associate_agent_with_custom_role
  end

  private

  def associate_agent_with_custom_role
    @agent.current_account_user.update!(custom_role_id: params[:custom_role_id])
  end
end
```

Aqui o padrão é diferente do `ReportPolicy` — a extensão chama `super` **primeiro** e faz algo
**depois**, em vez de decidir se chama `super` condicionalmente. Os dois estilos existem no
código real; não assuma um único padrão de `prepend`.

## Escala — quantos arquivos usam isso

`grep -rn "prepend_mod_with\|include_mod_with" app/ | wc -l` → **81 ocorrências**, em 51
arquivos distintos só em `app/` (sem contar o lado `enterprise/`).

## Subpastas de `app/` vs `enterprise/app/` — onde existe espelho hoje

`app/` (`ls app`): `actions, assets, builders, channels, controllers, dashboards, dispatchers,
drops, fields, finders, helpers, javascript, jobs, listeners, mailboxes, mailers, models,
policies, presenters, services, views`

`enterprise/app/` (`ls enterprise/app`): `builders, controllers, dispatchers, drops, fields,
finders, helpers, jobs, listeners, mailers, models, policies, presenters, services, views`

**Sem overlay hoje** (existem em `app/` mas não em `enterprise/app/`): `actions`, `assets`,
`channels`, `dashboards`, `javascript`, `mailboxes`.

## Duas categorias de conteúdo dentro de uma pasta espelhada — não confundir

Dentro de, por exemplo, `enterprise/app/models/`, coexistem dois tipos de arquivo bem
diferentes:

1. **Extensões de algo do core**, sempre um nível mais fundo sob um sub-namespace
   `enterprise/`: `enterprise/app/models/enterprise/account.rb`
   (`Enterprise::Account`), `enterprise/app/models/enterprise/concerns/account.rb`, etc. —
   correspondem a uma chamada `prepend_mod_with`/`include_mod_with` no lado core.
2. **Modelos/serviços 100% novos, exclusivos do enterprise**, direto na pasta espelhada, sem
   sub-nesting extra e **sem correspondente no core**: `enterprise/app/models/
   account_saml_settings.rb` (`class AccountSamlSettings < ApplicationRecord`, confirmado que
   não existe `app/models/account_saml_settings.rb`). Outros exemplos no mesmo diretório:
   `agent_capacity_policy.rb`, `applied_sla.rb`, `article_embedding.rb`, `call.rb`,
   `company.rb`, `copilot_message.rb`, `copilot_thread.rb`, `custom_role.rb`,
   `inbox_capacity_limit.rb`, `sla_event.rb`, `sla_policy.rb`, e um subdiretório `captain/`.

Só a categoria 1 é relevante para esta skill — a categoria 2 é código enterprise
independente, sem nada pra "sincronizar" no core.
