# Task: Atribuição de Agentes a Pipelines e Oportunidades — Backend

## Objetivo

Hoje **qualquer agente da conta vê e mexe em todos os pipelines** — não existe `PipelinePolicy::Scope`
nem conceito de membership (confirmado em `app/policies/pipeline_policy.rb`, que só tem
`index?/show? = true`). Esta task introduz:

1. `pipeline_members` — agentes atribuídos a um pipeline (mirror de `team_members`, que por sua vez
   é o mesmo padrão de `inbox_members` mas com rotas aninhadas mais limpas).
2. `assignee_id` + `team_id` em `PipelineItem` (oportunidade) — mesmo padrão de `Conversation`.
3. Regra: só pode ser `assignee` de uma oportunidade um agente que seja membro do pipeline dela
   (administradores são sempre elegíveis, mesma lógica de bypass que `User#assigned_inboxes` já
   usa).
4. Restrição de visibilidade: agente só vê pipelines em que é membro — **igual às inboxes**
   (`InboxPolicy::Scope` + `User#assigned_inboxes`).

Pré-requisito da task `12-feat-pipeline-settings-page.md` (aba "Agentes") e da
`09-feat-pipeline-agent-assignment-frontend.md`.

---

## 1. Migrações (`db/migrate/`)

### `create_pipeline_members.rb`

```ruby
class CreatePipelineMembers < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_members do |t|
      t.bigint :pipeline_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end
    add_index :pipeline_members, [:pipeline_id, :user_id], unique: true
    add_index :pipeline_members, :user_id
    add_foreign_key :pipeline_members, :pipelines
    add_foreign_key :pipeline_members, :users
  end
end
```

### `add_assignee_and_team_to_pipeline_items.rb`

```ruby
class AddAssigneeAndTeamToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_items, :assignee_id, :bigint
    add_column :pipeline_items, :team_id, :bigint
    add_index :pipeline_items, :assignee_id
    add_index :pipeline_items, :team_id
    add_foreign_key :pipeline_items, :users, column: :assignee_id
    add_foreign_key :pipeline_items, :teams
  end
end
```

Rodar `bundle exec rails db:migrate` e conferir `db/schema.rb`.

---

## 2. Model novo — `app/models/pipeline_member.rb`

Mirror exato de `app/models/team_member.rb` (que já é o padrão mais simples de membership do
projeto, mais limpo que `inbox_member.rb` que carrega lógica de round-robin não aplicável aqui):

```ruby
class PipelineMember < ApplicationRecord
  belongs_to :user
  belongs_to :pipeline

  validates :user_id, uniqueness: { scope: :pipeline_id }
end
```

---

## 3. Alterações em models existentes

### `app/models/pipeline.rb`

Adicionar após `has_many :pipeline_items, through: :pipeline_stages`:

```ruby
has_many :pipeline_members, dependent: :destroy_async
has_many :members, through: :pipeline_members, source: :user

# Adds multiple members to the pipeline
def add_members(user_ids)
  members_to_create = user_ids.map { |user_id| { user_id: user_id } }
  created_members = pipeline_members.create(members_to_create)
  created_members.filter_map(&:user)
end

# Removes multiple members from the pipeline
def remove_members(user_ids)
  pipeline_members.where(user_id: user_ids).destroy_all
end
```

(mirror exato de `Team#add_members`/`remove_members`, sem `update_account_cache` — não existe
cache de conta associado a pipelines hoje).

### `app/models/user.rb`

Adicionar (próximo das associações de `inboxes`/`inbox_members`, ~linha 99-100):

```ruby
has_many :pipeline_members, dependent: :destroy_async
has_many :pipelines, through: :pipeline_members
```

E o método de visibilidade (mirror exato de `assigned_inboxes`, ~linha 136-138):

```ruby
def assigned_pipelines
  administrator? ? Current.account.pipelines : pipelines.where(account_id: Current.account.id)
end
```

### `app/models/pipeline_item.rb`

Adicionar as duas associações e a validação de membership:

```ruby
class PipelineItem < ApplicationRecord
  belongs_to :account
  belongs_to :pipeline_stage
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :team, optional: true

  validates :contact_id, presence: true
  validates :pipeline_stage_id, presence: true
  validate :assignee_must_be_pipeline_member

  delegate :pipeline, to: :pipeline_stage

  private

  def assignee_must_be_pipeline_member
    return if assignee_id.blank?
    return if assignee.administrator?
    return if pipeline.members.exists?(id: assignee_id)

    errors.add(:assignee_id, I18n.t('errors.pipeline_item.assignee_not_member'))
  end
end
```

Adicionar a chave de erro em `config/locales/en.yml` (dentro de `errors:`), seguindo o padrão de
`errors.custom_attribute_definition.key_conflict`:

```yaml
errors:
  pipeline_item:
    assignee_not_member: 'Assignee must be a member of the pipeline'
```

E o equivalente em `config/locales/pt_BR.yml`:

```yaml
errors:
  pipeline_item:
    assignee_not_member: 'O responsável precisa ser um agente atribuído ao pipeline'
```

---

## 4. Controller novo — `app/controllers/api/v1/accounts/pipeline_members_controller.rb`

Mirror exato de `app/controllers/api/v1/accounts/team_members_controller.rb`:

```ruby
class Api::V1::Accounts::PipelineMembersController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline
  before_action :check_authorization
  before_action :validate_member_id_params, only: [:create, :update, :destroy]

  def index
    @pipeline_members = @pipeline.members
  end

  def create
    ActiveRecord::Base.transaction do
      @pipeline_members = @pipeline.add_members(members_to_be_added_ids)
    end
  end

  def update
    ActiveRecord::Base.transaction do
      @pipeline.add_members(members_to_be_added_ids)
      @pipeline.remove_members(members_to_be_removed_ids)
    end
    @pipeline_members = @pipeline.members
    render action: 'create'
  end

  def destroy
    ActiveRecord::Base.transaction do
      @pipeline.remove_members(params[:user_ids])
    end
    head :ok
  end

  private

  def members_to_be_added_ids
    params[:user_ids] - current_members_ids
  end

  def members_to_be_removed_ids
    current_members_ids - params[:user_ids]
  end

  def current_members_ids
    @current_members_ids ||= @pipeline.members.pluck(:id)
  end

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:pipeline_id])
  end

  def validate_member_id_params
    invalid_ids = params[:user_ids].map(&:to_i) - @pipeline.account.user_ids
    render json: { error: 'Invalid User IDs' }, status: :unauthorized and return if invalid_ids.present?
  end
end
```

---

## 5. Policy nova — `app/policies/pipeline_member_policy.rb`

Seguir o padrão de `app/policies/team_policy.rb` (index? true para qualquer agente do pipeline,
create/update/destroy restritos a admin):

```ruby
class PipelineMemberPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
```

---

## 6. Rotas (`config/routes.rb`)

Dentro do bloco `resources :pipelines` (linha ~271, junto de `pipeline_stages`), mirror exato de
como `teams` aninha `team_members` (linha ~262-269):

```ruby
resources :pipelines do
  resources :pipeline_stages, only: [:index, :create, :show, :update, :destroy] do
    collection { post :reorder }
  end
  resources :pipeline_items, only: [:index]
  resources :pipeline_members, only: [:index, :create] do
    collection do
      delete :destroy
      patch :update
    end
  end
end
```

---

## 7. Views Jbuilder

### `app/views/api/v1/accounts/pipeline_members/index.json.jbuilder` e `create.json.jbuilder`

Mirror de `app/views/api/v1/accounts/team_members/index.json.jbuilder` (retorna lista de agentes):

```jbuilder
json.array! @pipeline_members do |member|
  json.partial! 'api/v1/models/agent', formats: [:json], resource: member
end
```

`create.json.jbuilder` (reaproveitado também por `update`, via `render action: 'create'`):

```jbuilder
json.array! @pipeline_members do |member|
  json.partial! 'api/v1/models/agent', formats: [:json], resource: member
end
```

### `app/views/api/v1/models/_pipeline_item.json.jbuilder`

Adicionar assignee e team ao partial existente:

```jbuilder
json.id resource.id
json.title resource.title
json.value resource.value
json.notes resource.notes
json.position resource.position
json.pipeline_stage_id resource.pipeline_stage_id
json.conversation_id resource.conversation_id
json.created_at resource.created_at
json.updated_at resource.updated_at
json.contact do
  json.id resource.contact.id
  json.name resource.contact.name
  json.email resource.contact.email
  json.phone_number resource.contact.phone_number
  json.avatar_url resource.contact.avatar_url
end
json.assignee resource.assignee, partial: 'api/v1/models/agent', as: :resource if resource.assignee
json.team resource.team, partial: 'api/v1/models/team', as: :resource if resource.team
```

(Confirmar que os partials `api/v1/models/_agent.json.jbuilder` e `_team.json.jbuilder` existem —
já são usados pelo jbuilder de `Conversation`.)

---

## 8. Controller de items — permitir `assignee_id`/`team_id`

### `app/controllers/api/v1/accounts/pipeline_items_controller.rb`

```ruby
def item_params
  params.require(:pipeline_item).permit(
    :pipeline_stage_id, :contact_id, :conversation_id,
    :title, :value, :notes, :position, :assignee_id, :team_id
  )
end
```

---

## 9. Restrição de visibilidade (Feature 9 do plano)

### `app/policies/pipeline_policy.rb`

```ruby
class PipelinePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user.assigned_pipelines
    end
  end

  def index?
    true
  end

  def show?
    Current.user.assigned_pipelines.include? record
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
```

### `app/controllers/api/v1/accounts/pipelines_controller.rb`

```ruby
def index
  @pipelines = policy_scope(Current.account.pipelines).includes(:pipeline_stages)
end

private

def fetch_pipeline
  @pipeline = policy_scope(Current.account.pipelines).find(params[:id])
end
```

### `app/controllers/api/v1/accounts/pipeline_stages_controller.rb`

```ruby
def fetch_pipeline
  @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
end
```

### `app/controllers/api/v1/accounts/pipeline_items_controller.rb`

```ruby
def fetch_pipeline
  @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
end
```

### `app/policies/pipeline_item_policy.rb`

Adicionar checagem de escopo em `show?`/`update?`/`destroy?`, mantendo `destroy?` restrito a admin:

```ruby
class PipelineItemPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    Current.user.assigned_pipelines.include?(record.pipeline)
  end

  def create?
    true
  end

  def update?
    Current.user.assigned_pipelines.include?(record.pipeline)
  end

  def destroy?
    @account_user.administrator? && Current.user.assigned_pipelines.include?(record.pipeline)
  end

  def reorder?
    true
  end
end
```

### `app/controllers/api/v1/accounts/pipeline_members_controller.rb`

Também restringir `fetch_pipeline` ao escopo do usuário:

```ruby
def fetch_pipeline
  @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
end
```

---

## 10. Swagger (opcional, seguir padrão de `swagger/paths/application/pipelines/`)

- `swagger/paths/application/pipelines/members/index.yml`, `create.yml`, `update.yml`, `delete.yml`.
- `swagger/definitions/resource/pipeline_member.yml` — array de `agent`.
- Atualizar `_pipeline_item.yml` com `assignee` e `team`.

---

## Verificação

```bash
# Como admin: criar pipeline e adicionar agente 5 como membro
curl -X POST /api/v1/accounts/1/pipelines/1/pipeline_members \
  -d '{"user_ids": [5]}'

# Atualizar lista de membros (substitui totalmente)
curl -X PATCH /api/v1/accounts/1/pipelines/1/pipeline_members \
  -d '{"user_ids": [5, 8]}'

# Atribuir oportunidade a um agente que É membro do pipeline (sucesso)
curl -X PATCH /api/v1/accounts/1/pipeline_items/10 \
  -d '{"pipeline_item": {"assignee_id": 5}}'

# Atribuir a um agente que NÃO é membro do pipeline (deve retornar 422)
curl -X PATCH /api/v1/accounts/1/pipeline_items/10 \
  -d '{"pipeline_item": {"assignee_id": 99}}'

# Logar como agente 5 (membro) e confirmar que GET /pipelines só retorna pipelines onde é membro
curl -X GET /api/v1/accounts/1/pipelines -H "api_access_token: TOKEN_AGENTE_5"

# Logar como agente sem nenhum pipeline atribuído — GET /pipelines deve retornar []
# Tentar acessar diretamente GET /pipelines/1 como esse agente — deve dar 404/403 (Pundit::NotAuthorizedError)
```

Confirmar: admin sempre vê e pode atribuir a qualquer pipeline; agente membro vê e edita seus
pipelines; agente não-membro não vê nem consegue acessar por ID direto.
