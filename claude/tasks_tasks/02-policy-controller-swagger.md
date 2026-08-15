# Task 02 — Backend: policy, controller, rotas, views, Swagger

Parte do Grupo A ([visão geral](00-visao-geral.md)). Depende da [01](01-schema-model-task.md).

## Objetivo

Expor `Task` via `Api::V1::Accounts::TasksController`, top-level (não aninhado), filtrável por
`contact_id`/`conversation_id`/`pipeline_item_id` — mesmo padrão de
`PipelineItemsController#index` (`app/controllers/api/v1/accounts/pipeline_items_controller.rb:10-22`).
Não vira sub-recurso de `pipeline_items` porque uma tarefa nasce de 3 contextos diferentes, não
só de um card.

## 1. Policy `app/policies/task_policy.rb`

Mirror de `PipelineItemPolicy` (`app/policies/pipeline_item_policy.rb`) — qualquer membro da
conta pode ler/criar/editar; `destroy?` restrito a admin ou ao próprio responsável (diferente do
Pipeline, aqui não há "pipeline pai" para herdar a regra):

```ruby
class TaskPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  def index? = true
  def show? = true
  def create? = true
  def update? = true

  def destroy?
    @account_user.administrator? || record.assignee_id == Current.user.id
  end
end
```

## 2. Controller `app/controllers/api/v1/accounts/tasks_controller.rb`

```ruby
class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController
  before_action :fetch_task, only: [:show, :update, :destroy, :complete]
  before_action :check_authorization

  def index
    items = policy_scope(Current.account.tasks.includes(:contact, :conversation, :pipeline_item, :assignee))
    items = items.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    items = items.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    items = items.where(pipeline_item_id: params[:pipeline_item_id]) if params[:pipeline_item_id].present?
    @tasks = items.order(due_date: :asc)
  end

  def show; end

  def create
    @task = Current.account.tasks.new(create_params)
    @task.assignee_id ||= Current.user.id
    @task.save!
  end

  def update
    @task.update!(update_params)
  end

  # PATCH /api/v1/accounts/:account_id/tasks/:id/complete
  def complete
    @task.update!(completed_at: Time.zone.now)
  end

  def destroy
    @task.destroy!
    head :ok
  end

  private

  def check_authorization
    authorize(@task || Task)
  end

  def fetch_task
    @task = policy_scope(Current.account.tasks).find(params[:id])
  end

  def create_params
    params.require(:task).permit(:title, :due_date, :contact_id, :conversation_id, :pipeline_item_id, :assignee_id)
  end

  def update_params
    params.require(:task).permit(:title, :due_date, :assignee_id)
  end
end
```

**Atenção (risco #4 da visão geral / plano aprovado)**: `update_params` não inclui
`completed_at` de propósito — conclusão passa só pela action `complete`, para deixar explícito
no controller o ponto único onde `completed_at` muda (facilita auditar depois). E `update!`
mudando `due_date` precisa resetar `reminder_sent_at` — ver task 04, que adiciona esse callback
no model (`before_save :reset_reminder_if_rescheduled`) para não ficar espalhado no controller.

## 3. Rotas — `config/routes.rb`

Adicionar ao lado do bloco de `pipeline_items` (`config/routes.rb:284-288`):

```ruby
resources :tasks, only: [:index, :create, :show, :update, :destroy] do
  member { patch :complete }
end
```

## 4. Views Jbuilder

`app/views/api/v1/accounts/tasks/index.json.jbuilder`:
```ruby
json.payload @tasks do |task|
  json.partial! 'api/v1/accounts/tasks/task', task: task
end
```

`app/views/api/v1/accounts/tasks/show.json.jbuilder`, `create.json.jbuilder`,
`update.json.jbuilder`, `complete.json.jbuilder` — todos:
```ruby
json.partial! 'api/v1/accounts/tasks/task', task: @task
```

`app/views/api/v1/accounts/tasks/_task.json.jbuilder`:
```ruby
json.id task.id
json.title task.title
json.due_date task.due_date
json.completed_at task.completed_at
json.contact_id task.contact_id
json.conversation_id task.conversation_id
json.pipeline_item_id task.pipeline_item_id
json.created_at task.created_at
json.updated_at task.updated_at
json.assignee do
  json.id task.assignee.id
  json.name task.assignee.name
  json.avatar_url task.assignee.avatar_url
end
```

## 5. Swagger

Seguir a skill `endpoint-api-swagger`: criar `swagger/paths/tasks.yml` com a tag correta
(seguir o padrão de `swagger/paths/pipeline_items.yml` como referência de shape — ler esse
arquivo antes de escrever o novo), registrar em `swagger/paths/index.yml`, e rodar `docker exec
chatwoot-noble-rails-1 bundle exec rails swagger:build` antes de considerar a task pronta —
qualquer request spec futura quebra via Skooma se o YAML não bater com a resposta real.

## Testes

Só escrever `spec/requests/api/v1/accounts/tasks_spec.rb` se pedirem explicitamente. Quando
pedido, cobrir pelo menos: index filtrado por cada um dos 3 params, create com/sem
`conversation_id`/`pipeline_item_id`, `complete` seta `completed_at`, `destroy` só permitido
pro assignee ou admin.

## Critério de pronto

- `bundle exec rails routes | grep tasks` mostra as rotas esperadas.
- Requests manuais (curl/Postman) para os 6 endpoints retornam o shape esperado.
- `bundle exec rails swagger:build` sem erro.
- `bundle exec rubocop -a` sem novos warnings.
