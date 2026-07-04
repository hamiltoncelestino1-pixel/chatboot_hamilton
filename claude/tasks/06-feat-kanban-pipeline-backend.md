# Task: Kanban / CRM Pipeline — Backend (API + DB)

## Objetivo

Criar a API REST completa do módulo de Pipeline CRM, com 3 novas tabelas (`pipelines`, `pipeline_stages`, `pipeline_items`), models, controllers, policies, views Jbuilder, rotas e documentação Swagger — tudo seguindo o padrão já estabelecido no projeto.

---

## 1. Migrações (`db/migrate/`)

Criar 3 migrações em sequência (nomes com timestamp real):

### `create_pipelines.rb`
```ruby
class CreatePipelines < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false, limit: 255
      t.text :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :pipelines, [:account_id, :name], unique: true
    add_index :pipelines, [:account_id, :position]
  end
end
```

### `create_pipeline_stages.rb`
```ruby
class CreatePipelineStages < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_stages do |t|
      t.references :account, null: false, index: true
      t.references :pipeline, null: false, index: true
      t.string :name, null: false, limit: 255
      t.string :color, null: false, default: '#1f93ff', limit: 10
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :pipeline_stages, [:pipeline_id, :name], unique: true
    add_index :pipeline_stages, [:pipeline_id, :position]
  end
end
```

### `create_pipeline_items.rb`
```ruby
class CreatePipelineItems < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_items do |t|
      t.references :account, null: false, index: true
      t.references :pipeline_stage, null: false, index: true
      t.references :contact, null: false, index: true
      t.references :conversation, null: true, index: true
      t.string :title, limit: 255
      t.decimal :value, precision: 15, scale: 2, default: 0
      t.text :notes
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :pipeline_items, [:pipeline_stage_id, :position]
    add_index :pipeline_items, [:account_id, :contact_id]
  end
end
```

---

## 2. Models (`app/models/`)

### `pipeline.rb`
```ruby
class Pipeline < ApplicationRecord
  belongs_to :account
  has_many :pipeline_stages, -> { order(:position) }, dependent: :destroy_async
  has_many :pipeline_items, through: :pipeline_stages

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :account_id }

  default_scope { order(:position) }

  def push_event_data
    { id: id, name: name, position: position }
  end
end
```

### `pipeline_stage.rb`
```ruby
class PipelineStage < ApplicationRecord
  belongs_to :account
  belongs_to :pipeline
  has_many :pipeline_items, -> { order(:position) }, dependent: :destroy_async

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :pipeline_id }

  def push_event_data
    { id: id, name: name, color: color, position: position, pipeline_id: pipeline_id }
  end
end
```

### `pipeline_item.rb`
```ruby
class PipelineItem < ApplicationRecord
  belongs_to :account
  belongs_to :pipeline_stage
  belongs_to :contact
  belongs_to :conversation, optional: true

  validates :contact_id, presence: true
  validates :pipeline_stage_id, presence: true

  delegate :pipeline, to: :pipeline_stage
end
```

### Associações a adicionar em models existentes

**`app/models/account.rb`** — após as `has_many` existentes:
```ruby
has_many :pipelines, dependent: :destroy_async
has_many :pipeline_stages, dependent: :destroy_async
has_many :pipeline_items, dependent: :destroy_async
```

**`app/models/contact.rb`** — após as `has_many` existentes:
```ruby
has_many :pipeline_items, dependent: :destroy_async
```

---

## 3. Policies (`app/policies/`)

Seguir exatamente o padrão de `app/policies/team_policy.rb`.

### `pipeline_policy.rb`
```ruby
class PipelinePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
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

### `pipeline_stage_policy.rb`
```ruby
class PipelineStagePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
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

  def reorder?
    @account_user.administrator?
  end
end
```

### `pipeline_item_policy.rb`
```ruby
class PipelineItemPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    @account_user.administrator?
  end

  def reorder?
    true
  end
end
```

---

## 4. Controllers (`app/controllers/api/v1/accounts/`)

### `pipelines_controller.rb`
```ruby
class Api::V1::Accounts::PipelinesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @pipelines = Current.account.pipelines.includes(:pipeline_stages)
  end

  def show; end

  def create
    @pipeline = Current.account.pipelines.new(pipeline_params)
    @pipeline.save!
  end

  def update
    @pipeline.update!(pipeline_params)
  end

  def destroy
    @pipeline.destroy!
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :description, :position)
  end
end
```

### `pipeline_stages_controller.rb`

Aninhado em pipelines (`params[:pipeline_id]`):
```ruby
class Api::V1::Accounts::PipelineStagesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline
  before_action :fetch_stage, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @stages = @pipeline.pipeline_stages.includes(:pipeline_items)
  end

  def show; end

  def create
    @stage = @pipeline.pipeline_stages.new(stage_params.merge(account: Current.account))
    @stage.save!
  end

  def update
    @stage.update!(stage_params)
  end

  def destroy
    @stage.destroy!
    head :ok
  end

  # POST /api/v1/accounts/:account_id/pipelines/:pipeline_id/pipeline_stages/reorder
  # Body: { ordered_ids: [3, 1, 2] }
  def reorder
    ordered_ids = params[:ordered_ids]
    ordered_ids.each_with_index do |stage_id, index|
      @pipeline.pipeline_stages.find(stage_id).update_column(:position, index)
    end
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:pipeline_id])
  end

  def fetch_stage
    @stage = @pipeline.pipeline_stages.find(params[:id])
  end

  def stage_params
    params.require(:pipeline_stage).permit(:name, :color, :position)
  end
end
```

### `pipeline_items_controller.rb`

Suporta listagem aninhada em pipeline e CRUD independente:
```ruby
class Api::V1::Accounts::PipelineItemsController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:index]
  before_action :fetch_item, only: [:show, :update, :destroy]
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/pipelines/:pipeline_id/pipeline_items
  # Suporta ?stage_id=X para filtrar por coluna
  def index
    @items = pipeline_items_scope
    @items = @items.where(pipeline_stage_id: params[:stage_id]) if params[:stage_id].present?
  end

  def show; end

  def create
    @item = Current.account.pipeline_items.new(item_params)
    @item.save!
  end

  def update
    @item.update!(item_params)
  end

  def destroy
    @item.destroy!
    head :ok
  end

  # POST /api/v1/accounts/:account_id/pipeline_items/reorder
  # Body: { stage_id: 1, ordered_ids: [5, 2, 8] }
  def reorder
    stage = Current.account.pipeline_stages.find(params[:stage_id])
    params[:ordered_ids].each_with_index do |item_id, index|
      stage.pipeline_items.find(item_id).update_column(:position, index)
    end
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = Current.account.pipelines.find(params[:pipeline_id])
  end

  def fetch_item
    @item = Current.account.pipeline_items.find(params[:id])
  end

  def pipeline_items_scope
    @pipeline
      .pipeline_items
      .includes(:contact, :conversation, :pipeline_stage)
      .order('pipeline_stage_id, position')
  end

  def item_params
    params.require(:pipeline_item).permit(
      :pipeline_stage_id, :contact_id, :conversation_id,
      :title, :value, :notes, :position
    )
  end
end
```

---

## 5. Views Jbuilder

### Partials (`app/views/api/v1/models/`)

**`_pipeline.json.jbuilder`**
```jbuilder
json.id resource.id
json.name resource.name
json.description resource.description
json.position resource.position
json.account_id resource.account_id
json.stages_count resource.pipeline_stages.size
json.created_at resource.created_at
json.updated_at resource.updated_at
```

**`_pipeline_stage.json.jbuilder`**
```jbuilder
json.id resource.id
json.name resource.name
json.color resource.color
json.position resource.position
json.pipeline_id resource.pipeline_id
json.account_id resource.account_id
json.items_count resource.pipeline_items.size
json.created_at resource.created_at
json.updated_at resource.updated_at
```

**`_pipeline_item.json.jbuilder`**
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
```

### Views por recurso

Estrutura (cada recurso tem `index.json.jbuilder` e `show.json.jbuilder`):

**`app/views/api/v1/accounts/pipelines/index.json.jbuilder`**
```jbuilder
json.array! @pipelines do |pipeline|
  json.partial! 'api/v1/models/pipeline', formats: [:json], resource: pipeline
  json.stages pipeline.pipeline_stages do |stage|
    json.partial! 'api/v1/models/pipeline_stage', formats: [:json], resource: stage
  end
end
```

**`app/views/api/v1/accounts/pipelines/show.json.jbuilder`**
```jbuilder
json.partial! 'api/v1/models/pipeline', formats: [:json], resource: @pipeline
json.stages @pipeline.pipeline_stages do |stage|
  json.partial! 'api/v1/models/pipeline_stage', formats: [:json], resource: stage
end
```

**`app/views/api/v1/accounts/pipeline_stages/index.json.jbuilder`**
```jbuilder
json.array! @stages do |stage|
  json.partial! 'api/v1/models/pipeline_stage', formats: [:json], resource: stage
end
```

**`app/views/api/v1/accounts/pipeline_items/index.json.jbuilder`**
```jbuilder
json.array! @items do |item|
  json.partial! 'api/v1/models/pipeline_item', formats: [:json], resource: item
end
```

Criar também `show.json.jbuilder` para stages e items seguindo o mesmo padrão.

---

## 6. Rotas (`config/routes.rb`)

Dentro do bloco `scope module: :accounts` (junto com teams, conversations, etc.):

```ruby
resources :pipelines do
  scope module: :pipelines do
    resources :pipeline_stages, only: [:index, :create, :show, :update, :destroy] do
      collection { post :reorder }
    end
    resources :pipeline_items, only: [:index]
  end
end

resources :pipeline_items, only: [:create, :show, :update, :destroy] do
  collection { post :reorder }
end
```

---

## 7. Swagger (`swagger/`)

### Paths — criar pasta `swagger/paths/application/pipelines/` com:

- `index.yml` — GET lista pipelines (response: array de pipeline com stages embutidos)
- `create.yml` — POST cria pipeline
- `show.yml` — GET pipeline por ID
- `update.yml` — PATCH atualiza pipeline
- `delete.yml` — DELETE pipeline
- `stages/index.yml`, `stages/create.yml`, `stages/update.yml`, `stages/delete.yml`, `stages/reorder.yml`
- `items/index.yml`, `items/create.yml`, `items/update.yml`, `items/delete.yml`, `items/reorder.yml`

### Schemas — `swagger/definitions/`

**`resource/pipeline.yml`**
```yaml
type: object
properties:
  id:
    type: number
  name:
    type: string
  description:
    type: string
  position:
    type: number
  account_id:
    type: number
  stages_count:
    type: number
  created_at:
    type: string
    format: date-time
```

**`resource/pipeline_stage.yml`** — id, name, color, position, pipeline_id, items_count

**`resource/pipeline_item.yml`** — id, title, value, notes, position, pipeline_stage_id, contact (object), conversation_id

**`request/pipeline/create_update_payload.yml`** — name (required), description, position

**`request/pipeline_stage/create_update_payload.yml`** — name (required), color, position

**`request/pipeline_stage/reorder_payload.yml`** — ordered_ids (array of numbers, required)

**`request/pipeline_item/create_update_payload.yml`** — pipeline_stage_id, contact_id, title, value, notes, position

### Atualizar índices

`swagger/paths/index.yml` — adicionar referências às novas pastas
`swagger/definitions/index.yml` — registrar novos schemas
`swagger/index.yml` — adicionar tag `Pipelines` na lista de tags

---

## Verificação

```bash
# Criar pipeline
curl -X POST /api/v1/accounts/1/pipelines \
  -H "api_access_token: TOKEN" \
  -d '{"name": "Vendas", "description": "Funil principal"}'

# Criar stages
curl -X POST /api/v1/accounts/1/pipelines/1/pipeline_stages \
  -d '{"name": "Lead", "color": "#f59e0b"}'

# Criar item (card)
curl -X POST /api/v1/accounts/1/pipeline_items \
  -d '{"pipeline_stage_id": 1, "contact_id": 5, "title": "Proposta ABC", "value": 5000}'

# Mover para outra stage
curl -X PATCH /api/v1/accounts/1/pipeline_items/1 \
  -d '{"pipeline_stage_id": 2}'

# Reordenar stages
curl -X POST /api/v1/accounts/1/pipelines/1/pipeline_stages/reorder \
  -d '{"ordered_ids": [3, 1, 2]}'

# Reordenar cards dentro de uma stage
curl -X POST /api/v1/accounts/1/pipeline_items/reorder \
  -d '{"stage_id": 2, "ordered_ids": [8, 5, 12]}'

# Listar pipeline com stages (para montar o board)
curl -X GET /api/v1/accounts/1/pipelines/1
```

Confirmar que admins podem criar/deletar e agentes podem criar/mover items mas não deletar.
