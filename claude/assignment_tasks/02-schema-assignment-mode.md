# Task: Validação `assignment_mode` no jsonb da Inbox + controller

## Objetivo

Adicionar a chave `assignment_mode` (`'round_robin'` | `'balanced'`) dentro do jsonb já
existente `inboxes.auto_assignment_config`, com validação dos valores aceitos, e liberar o
controller a receber esse campo (junto com `restrict_to_online_agents`, usado pelas tasks
`05`/`06`). **Sem migration de schema** — `auto_assignment_config` já existe como coluna jsonb.

Esta task só prepara model + controller. A lógica de seleção que efetivamente **usa**
`assignment_mode` fica na task `03`; a UI que grava esse valor fica na task `04`.

---

## Contexto importante

Validação já existente como referência de padrão exato a seguir,
`app/models/inbox.rb`:
```ruby
validate :ensure_valid_max_assignment_limit
```
```ruby
def ensure_valid_max_assignment_limit
  # overridden in enterprise/app/models/enterprise/inbox.rb
end
```

Implementação real em `enterprise/app/models/enterprise/inbox.rb`:
```ruby
def ensure_valid_max_assignment_limit
  return if auto_assignment_config['max_assignment_limit'].blank?
  return if auto_assignment_config['max_assignment_limit'].to_i.positive?

  errors.add(:auto_assignment_config, 'max_assignment_limit must be greater than 0')
end
```

Controller que hoje permite só `max_assignment_limit`,
`enterprise/app/controllers/enterprise/api/v1/accounts/inboxes_controller.rb`:
```ruby
module Enterprise::Api::V1::Accounts::InboxesController
  def inbox_attributes
    super + ee_inbox_attributes
  end

  def ee_inbox_attributes
    [auto_assignment_config: [:max_assignment_limit]]
  end
  ...
end
```
Esse módulo é `prepend_mod_with`'d no controller base (`app/controllers/api/v1/accounts/inboxes_controller.rb`),
carregado sempre neste fork (`enterprise/` sempre presente).

---

## 1. `app/models/inbox.rb`

```diff
   validate :ensure_valid_max_assignment_limit
+  validate :ensure_valid_assignment_mode
```
```diff
   def ensure_valid_max_assignment_limit
     # overridden in enterprise/app/models/enterprise/inbox.rb
   end
+
+  def ensure_valid_assignment_mode
+    # overridden in enterprise/app/models/enterprise/inbox.rb
+  end
```

## 2. `enterprise/app/models/enterprise/inbox.rb`

```diff
 module Enterprise::Inbox
+  ASSIGNMENT_MODES = %w[round_robin balanced].freeze
+
   def member_ids_with_assignment_capacity
     ...
   end
   ...
   def ensure_valid_max_assignment_limit
     return if auto_assignment_config['max_assignment_limit'].blank?
     return if auto_assignment_config['max_assignment_limit'].to_i.positive?

     errors.add(:auto_assignment_config, 'max_assignment_limit must be greater than 0')
   end
+
+  def ensure_valid_assignment_mode
+    mode = auto_assignment_config['assignment_mode']
+    return if mode.blank?
+    return if ASSIGNMENT_MODES.include?(mode)
+
+    errors.add(:auto_assignment_config, "assignment_mode must be one of #{ASSIGNMENT_MODES.join(', ')}")
+  end
 end
```

`assignment_mode` ausente/`nil` é válido (default implícito = round robin, tratado na task `03`
como fallback quando a chave não existe). `restrict_to_online_agents` **não** precisa de
validação de formato — é boolean livre, lido via `ActiveModel::Type::Boolean.new.cast` nas
tasks `05`/`06`, que já tolera `nil`/string/boolean sem lançar erro.

## 3. `enterprise/app/controllers/enterprise/api/v1/accounts/inboxes_controller.rb`

```diff
   def ee_inbox_attributes
-    [auto_assignment_config: [:max_assignment_limit]]
+    [auto_assignment_config: [:max_assignment_limit, :assignment_mode, :restrict_to_online_agents]]
   end
```

---

## Verificação

- Novo spec ou extensão de `spec/enterprise/models/inbox_spec.rb` (verificar se já existe um
  `describe` para `ensure_valid_max_assignment_limit` e adicionar ao lado):
  ```ruby
  describe '#ensure_valid_assignment_mode' do
    it 'accepts round_robin' do
      inbox.auto_assignment_config = { 'assignment_mode' => 'round_robin' }
      expect(inbox).to be_valid
    end

    it 'accepts balanced' do
      inbox.auto_assignment_config = { 'assignment_mode' => 'balanced' }
      expect(inbox).to be_valid
    end

    it 'accepts blank/absent' do
      inbox.auto_assignment_config = {}
      expect(inbox).to be_valid
    end

    it 'rejects invalid values' do
      inbox.auto_assignment_config = { 'assignment_mode' => 'invalid_mode' }
      expect(inbox).not_to be_valid
      expect(inbox.errors[:auto_assignment_config]).to be_present
    end
  end
  ```
- Estender `spec/enterprise/controllers/enterprise/api/v1/accounts/inboxes_controller_spec.rb`
  (buscar os testes já existentes de `auto_assignment_config`/`max_assignment_limit` como
  referência de formato) cobrindo que um `PATCH` com
  `{ auto_assignment_config: { assignment_mode: 'balanced', restrict_to_online_agents: true } }`
  é aceito e persistido.
- Manual: via `bin/rails console`,
  ```ruby
  inbox = Inbox.first
  inbox.update(auto_assignment_config: { assignment_mode: 'balanced' })
  inbox.reload.auto_assignment_config # => { "assignment_mode" => "balanced" }
  inbox.update(auto_assignment_config: { assignment_mode: 'xyz' }) # => false, com erro em auto_assignment_config
  ```
- `bundle exec rubocop` limpo nos arquivos alterados.
