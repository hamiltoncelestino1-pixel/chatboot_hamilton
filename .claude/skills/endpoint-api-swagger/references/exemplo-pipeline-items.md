# Exemplo completo e real — endpoint `pipeline_items`

Todo o código abaixo foi lido verbatim do repositório nesta sessão.

## Controller — `app/controllers/api/v1/accounts/pipeline_items_controller.rb`

```ruby
class Api::V1::Accounts::PipelineItemsController < Api::V1::Accounts::BaseController
  before_action :fetch_item, only: [:show, :update, :destroy, :export]
  before_action :check_authorization

  rescue_from Pipelines::ExportItemService::SamePipelineError,
              Pipelines::ExportItemService::InvalidTargetStageError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    return nested_pipeline_index if params[:pipeline_id].present?

    items = policy_scope(
      Current.account.pipeline_items
             .joins(:pipeline_stage)
             .where(pipeline_stages: { pipeline_id: policy_scope(Current.account.pipelines).select(:id) })
             .includes(:contact, :conversation, :assignee, :team, pipeline_stage: :pipeline)
    )
    items = items.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    items = items.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    @items = items.order(created_at: :desc)
  end

  def show; end

  def create
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    Current.account.pipeline_stages
           .where(pipeline_id: allowed_pipeline_ids)
           .find(create_params[:pipeline_stage_id])
    @item = Current.account.pipeline_items.new(create_params)
    @item.save!
    Pipelines::AutoAssignmentService.new(pipeline_item: @item).perform
  end

  def update
    @item.update!(update_params)
    @item.association(:assignee).reset if update_params.key?(:assignee_id)
    @item.association(:team).reset if update_params.key?(:team_id)
    @item.association(:pipeline_stage).reset if update_params.key?(:pipeline_stage_id)
  end

  def destroy
    @item.destroy!
    head :ok
  end

  # POST /api/v1/accounts/:account_id/pipeline_items/:id/export
  # Body: { pipeline_item: { target_pipeline_id: 3, target_stage_id: 12 } }
  def export
    target_pipeline = policy_scope(Current.account.pipelines).find(export_params[:target_pipeline_id])
    @item = Pipelines::ExportItemService.new(
      pipeline_item: @item,
      target_pipeline: target_pipeline,
      target_stage_id: export_params[:target_stage_id]
    ).perform
    render :show
  end

  # POST /api/v1/accounts/:account_id/pipeline_items/reorder
  # Body: { stage_id: 1, ordered_ids: [5, 2, 8] }
  def reorder
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    stage = Current.account.pipeline_stages
                   .joins(:pipeline)
                   .where(pipeline_id: allowed_pipeline_ids)
                   .find(params[:stage_id])
    visible_item_ids = policy_scope(stage.pipeline_items).pluck(:id)
    params[:ordered_ids].each_with_index do |item_id, index|
      next unless visible_item_ids.include?(item_id.to_i)

      stage.pipeline_items.find(item_id).update_column(:position, index)
    end
    head :ok
  end

  private

  def nested_pipeline_index
    @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
    @items = pipeline_items_scope
    @items = @items.where(pipeline_stage_id: params[:stage_id]) if params[:stage_id].present?
    render :index
  end

  def fetch_item
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    @item = policy_scope(
      Current.account.pipeline_items
             .joins(:pipeline_stage)
             .where(pipeline_stages: { pipeline_id: allowed_pipeline_ids })
             .includes(:contact, :assignee, :team, pipeline_stage: :pipeline)
    ).find(params[:id])
  end

  def pipeline_items_scope
    policy_scope(
      @pipeline.pipeline_items
               .includes(:contact, :conversation, :assignee, :team, pipeline_stage: :pipeline)
    ).order('pipeline_stage_id, position')
  end

  def create_params
    params.require(:pipeline_item).permit(
      :pipeline_stage_id, :contact_id, :conversation_id,
      :title, :value, :notes, :position, :assignee_id, :team_id,
      custom_attributes: {}
    )
  end

  def update_params
    params.require(:pipeline_item).permit(
      :pipeline_stage_id, :conversation_id,
      :title, :value, :notes, :position, :assignee_id, :team_id,
      custom_attributes: {}
    )
  end

  def export_params
    params.require(:pipeline_item).permit(:target_pipeline_id, :target_stage_id)
  end
end
```

Padrões a notar:
- `check_authorization` sem argumentos infere a policy `PipelineItem` a partir do nome do
  controller.
- Toda query passa por `policy_scope(...)`, inclusive lookups aninhados
  (`policy_scope(Current.account.pipelines).find(...)` dentro de `fetch_item`/`export`/
  `reorder`).
- `render :show` chamado explicitamente em `export` pra reusar a view padrão.
- `head :ok` (não `:no_content`) em `destroy` e `reorder`.
- `rescue_from` de exceções de service mapeando pra `422` com `{ error: e.message }`.

## Views Jbuilder — `app/views/api/v1/accounts/pipeline_items/`

**`index.json.jbuilder`**:
```ruby
json.array! @items do |item|
  json.partial! 'api/v1/models/pipeline_item', formats: [:json], resource: item
end
```

**`show.json.jbuilder`**:
```ruby
json.partial! 'api/v1/models/pipeline_item', formats: [:json], resource: @item
```

**`create.json.jbuilder`** e **`update.json.jbuilder`** — idênticos a `show.json.jbuilder`:
```ruby
json.partial! 'api/v1/models/pipeline_item', formats: [:json], resource: @item
```

`destroy` não tem view (`head :ok` no controller).

## Rotas — `config/routes.rb` (linhas 271-288)

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

resources :pipeline_items, only: [:index, :create, :show, :update, :destroy] do
  collection { post :reorder }
  member { post :export }
  resource :labels, only: [:index, :create], module: :pipeline_items
end
```

Duas declarações de rota para `pipeline_items`: uma aninhada só-`index` sob `pipelines`
(`/pipelines/:pipeline_id/pipeline_items`, tratada por `nested_pipeline_index`), e uma CRUD
completa no nível superior (`/pipeline_items`) com `collection`/`member` para as actions
extras.

## Swagger — estrutura de arquivos

```
swagger/index.yml                                   # documento raiz, $ref pra tudo
swagger/paths/index.yml                              # mapa de paths → arquivo de operação
swagger/paths/application/pipelines/items/*.yml       # um arquivo por operação
swagger/definitions/index.yml                         # registro de schemas
swagger/definitions/resource/pipeline_item.yml         # schema de resposta
swagger/parameters/index.yml                           # registro de parâmetros reutilizáveis
swagger/parameters/pipeline_item_id.yml                 # parâmetro de path reutilizável
swagger/swagger.json                                   # GERADO, não editar à mão
```

**`swagger/paths/index.yml`** (trecho, linhas 576-609):
```yaml
/api/v1/accounts/{account_id}/pipelines/{pipeline_id}/pipeline_items:
  parameters:
    - $ref: '#/components/parameters/account_id'
    - $ref: '#/components/parameters/pipeline_id'
  get:
    $ref: ./application/pipelines/items/index.yml
/api/v1/accounts/{account_id}/pipeline_items:
  parameters:
    - $ref: '#/components/parameters/account_id'
  post:
    $ref: ./application/pipelines/items/create.yml
/api/v1/accounts/{account_id}/pipeline_items/{pipeline_item_id}:
  parameters:
    - $ref: '#/components/parameters/account_id'
    - $ref: '#/components/parameters/pipeline_item_id'
  get:
    $ref: ./application/pipelines/items/index.yml
  patch:
    $ref: ./application/pipelines/items/update.yml
  delete:
    $ref: ./application/pipelines/items/delete.yml
/api/v1/accounts/{account_id}/pipeline_items/reorder:
  parameters:
    - $ref: '#/components/parameters/account_id'
  post:
    $ref: ./application/pipelines/items/reorder.yml
/api/v1/accounts/{account_id}/pipeline_items/{pipeline_item_id}/labels:
  parameters:
    - $ref: '#/components/parameters/account_id'
    - $ref: '#/components/parameters/pipeline_item_id'
  get:
    $ref: ./application/pipelines/items/labels/index.yml
  post:
    $ref: ./application/pipelines/items/labels/create.yml
```

**`swagger/paths/application/pipelines/items/index.yml`** (completo):
```yaml
tags:
  - Pipelines
operationId: list-pipeline-items
summary: List pipeline items
security:
  - userApiKey: []
description: List all items for a given pipeline. Pass ?stage_id=X to filter by stage.
responses:
  '200':
    description: Success
    content:
      application/json:
        schema:
          type: array
          items:
            $ref: '#/components/schemas/pipeline_item'
  '401':
    description: Unauthorized
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/bad_request_error'
```

**`swagger/paths/application/pipelines/items/create.yml`** (completo):
```yaml
tags:
  - Pipelines
operationId: create-a-pipeline-item
summary: Create a pipeline item
security:
  - userApiKey: []
description: Create a new card/item in a pipeline stage
requestBody:
  required: true
  content:
    application/json:
      schema:
        $ref: '#/components/schemas/pipeline_item_create_update_payload'
responses:
  '200':
    description: Success
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/pipeline_item'
  '401':
    description: Unauthorized
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/bad_request_error'
```

`update.yml`/`delete.yml` seguem o mesmo padrão (`operationId: update-a-pipeline-item` /
`delete-a-pipeline-item`, respostas 200/401; `update` também exige o mesmo
`pipeline_item_create_update_payload` no `requestBody`).

**`swagger/definitions/resource/pipeline_item.yml`** (schema de resposta, completo):
```yaml
type: object
properties:
  id:
    type: number
    description: The ID of the pipeline item
  title:
    type:
      - string
      - 'null'
    description: The title of the item (card)
  value:
    type: number
    description: The monetary value associated with this deal
  notes:
    type:
      - string
      - 'null'
    description: Additional notes about the item
  position:
    type: number
    description: The display order position within the stage
  pipeline_stage_id:
    type: number
    description: The ID of the stage this item belongs to
  conversation_id:
    type:
      - number
      - 'null'
    description: The ID of the linked conversation, if any
  contact:
    type: object
    properties:
      id:
        type: number
      name:
        type: string
      email:
        type:
          - string
          - 'null'
      phone_number:
        type:
          - string
          - 'null'
      avatar_url:
        type: string
  assignee_id:
    type:
      - integer
      - 'null'
    description: The ID of the agent assigned to this item
  team_id:
    type:
      - integer
      - 'null'
    description: The ID of the team assigned to this item
  assignee:
    $ref: '#/components/schemas/agent'
  team:
    $ref: '#/components/schemas/team'
  created_at:
    type: string
    format: date-time
    description: The date and time when the item was created
  updated_at:
    type: string
    format: date-time
    description: The date and time when the item was last updated
```

**Registro em `swagger/definitions/index.yml`** (trecho):
```yaml
pipeline:
  $ref: ./resource/pipeline.yml
pipeline_stage:
  $ref: ./resource/pipeline_stage.yml
pipeline_item:
  $ref: ./resource/pipeline_item.yml
# ...
pipeline_item_create_update_payload:
  $ref: ./request/pipeline_item/create_update_payload.yml
pipeline_item_reorder_payload:
  $ref: ./request/pipeline_item/reorder_payload.yml
```

**`swagger/parameters/pipeline_item_id.yml`** (completo):
```yaml
in: path
name: pipeline_item_id
schema:
  type: integer
required: true
description: The ID of the pipeline item
```

**Registro em `swagger/parameters/index.yml`** (trecho):
```yaml
pipeline_id:
  $ref: ./pipeline_id.yml
pipeline_stage_id:
  $ref: ./pipeline_stage_id.yml
pipeline_item_id:
  $ref: ./pipeline_item_id.yml
```

## Rake task de build — `lib/tasks/swagger.rake`

```ruby
require 'json_refs'
require 'fileutils'
require 'pathname'
require 'yaml'
require 'json'

module SwaggerTaskActions
  def self.execute_build
    swagger_dir = Rails.root.join('swagger')
    index_yml_relative_path = 'index.yml'
    swagger_json_relative_path = 'swagger.json'

    Dir.chdir(swagger_dir) do
      swagger_index_content = File.read(index_yml_relative_path)
      swagger_index = YAML.safe_load(swagger_index_content)

      final_build = JsonRefs.call(
        swagger_index,
        resolve_local_ref: false,
        resolve_file_ref: true,
        logging: true
      )
      File.write(swagger_json_relative_path, JSON.pretty_generate(final_build))

      absolute_swagger_json_path = swagger_dir.join(swagger_json_relative_path)
      puts 'Swagger build was successful.'
      puts "Generated #{absolute_swagger_json_path}"
      puts 'Go to http://localhost:3000/swagger see the changes.'

      Rake::Task['swagger:build_tag_groups'].invoke
    end
  end
end

namespace :swagger do
  desc 'build combined swagger.json file from all the fragmented definitions and paths inside swagger folder'
  task build: :environment do
    SwaggerTaskActions.execute_build
  end

  desc 'build separate swagger files for each tag group'
  task build_tag_groups: :environment do
    SwaggerTaskActions.execute_build_tag_groups
  end

  desc 'build swagger files and create symlinks in developer-docs'
  task build_for_docs: :environment do
    SwaggerTaskActions.execute_build_for_docs
  end
end
```

`rails swagger:build` lê `swagger/index.yml`, resolve recursivamente todo `$ref: ./arquivo.yml`
e escreve o resultado achatado em `swagger/swagger.json`, depois invoca automaticamente
`swagger:build_tag_groups`.

## Skooma — `spec/rails_helper.rb` (linhas 79-81)

```ruby
# OpenAPI response validation via Skooma
path_to_openapi = Rails.root.join('swagger/swagger.json')
config.include Skooma::RSpec[path_to_openapi], type: :request
```

Existe também `spec/swagger/openapi_spec.rb`, que valida o próprio documento contra o
meta-schema OpenAPI 3.1.0:
```ruby
require 'rails_helper'

RSpec.describe 'OpenAPI document', type: :request do
  it 'is valid against the OpenAPI 3.1.0 meta-schema' do
    expect(skooma_openapi_schema).to be_valid_document
  end
end
```

## Spec de exemplo — validação implícita do Skooma

`spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` (apesar do path, é
`type: :request`):

```ruby
RSpec.describe 'Pipeline Items API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:source_pipeline) { create(:pipeline, account: account) }
  let(:source_stage) { create(:pipeline_stage, pipeline: source_pipeline, account: account) }
  let(:target_pipeline) { create(:pipeline, account: account) }
  let(:target_stage) { create(:pipeline_stage, pipeline: target_pipeline, account: account) }
  let(:item) { create(:pipeline_item, pipeline_stage: source_stage, account: account) }

  before do
    source_pipeline.add_members([agent.id])
    target_pipeline.add_members([agent.id])
    item # force creation before tests
  end

  describe 'POST /api/v1/accounts/:account_id/pipeline_items' do
    context 'when authenticated' do
      let(:headers) { agent.create_new_auth_token }

      it 'returns 422 with the duplicate-card message when the contact already has a card in the pipeline' do
        existing_item = item
        contact = existing_item.contact

        post "/api/v1/accounts/#{account.id}/pipeline_items",
             params: {
               pipeline_item: {
                 pipeline_stage_id: source_stage.id,
                 contact_id: contact.id
               }
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include(
          I18n.t('errors.pipeline_item.duplicate_contact_in_pipeline')
        )
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pipeline_items/:id/export' do
    context 'when authenticated' do
      let(:headers) { agent.create_new_auth_token }

      it 'exports the item to the target pipeline and stage' do
        post "/api/v1/accounts/#{account.id}/pipeline_items/#{item.id}/export",
             params: { pipeline_item: { target_pipeline_id: target_pipeline.id, target_stage_id: target_stage.id } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:success)
        expect(item.reload.pipeline_stage_id).to eq(target_stage.id)
        expect(response.parsed_body['id']).to eq(item.id)
      end
    end
  end
end
```

Note: **não existe nenhum `match_response_schema`/matcher de schema explícito**. A validação é
100% implícita, via `config.include Skooma::RSpec[...], type: :request` no `rails_helper.rb`.
Qualquer resposta HTTP feita dentro de uma spec `type: :request` é automaticamente checada
contra `swagger/swagger.json` — é isso que quebra silenciosamente quando alguém muda um
endpoint sem atualizar o Swagger.
