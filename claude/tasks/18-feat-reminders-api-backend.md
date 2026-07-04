# Task: Sistema de Lembretes — API REST

## Objetivo

Expor `Reminder` via API REST: CRUD completo + ação de marcar concluído + listagem filtrável
(status, vínculo, responsável, data), pronta pra ser consumida pelo frontend (tasks 19-21).

**Pré-requisitos:** tasks 15, 16 e 17 implementadas (o backend de lembretes já funciona ponta a
ponta via console antes desta task — aqui só adicionamos a superfície HTTP).

---

## 1. Rotas — `config/routes.rb`

Dentro do bloco de `resources :accounts` / `scope module: :accounts`, ao lado de `pipeline_items`:

```ruby
resources :reminders, only: [:index, :create, :show, :update, :destroy] do
  member { post :complete }
end
```

Endpoints resultantes:
- `GET /api/v1/accounts/:account_id/reminders` — lista com filtros
- `POST /api/v1/accounts/:account_id/reminders`
- `GET /api/v1/accounts/:account_id/reminders/:id`
- `PATCH/PUT /api/v1/accounts/:account_id/reminders/:id`
- `DELETE /api/v1/accounts/:account_id/reminders/:id`
- `POST /api/v1/accounts/:account_id/reminders/:id/complete`

---

## 2. Controller — `app/controllers/api/v1/accounts/reminders_controller.rb`

Mesmo esqueleto de `pipeline_items_controller.rb` (ver task 06 do Kanban):

```ruby
class Api::V1::Accounts::RemindersController < Api::V1::Accounts::BaseController
  before_action :fetch_reminder, only: [:show, :update, :destroy, :complete]
  before_action :check_authorization

  def index
    @reminders = ReminderFinder.new(user: Current.user, account: Current.account, params: params).perform
  end

  def show; end

  def create
    @reminder = Current.account.reminders.new(reminder_params.merge(created_by_id: Current.user.id))
    @reminder.save!
  end

  def update
    @reminder.update!(reminder_params)
  end

  def complete
    @reminder.mark_as_completed!
    render :show
  end

  def destroy
    @reminder.destroy!
    head :ok
  end

  private

  def fetch_reminder
    @reminder = Current.account.reminders.find(params[:id])
  end

  def reminder_params
    params.require(:reminder).permit(
      :title, :description, :due_at, :assignee_id, :team_id,
      :remindable_type, :remindable_id
    )
  end
end
```

`check_authorization` (Pundit, via `Api::V1::Accounts::BaseController`) já invoca `ReminderPolicy`
(task 15) automaticamente pra cada ação com o nome correspondente (`show?`, `update?`, `complete?`,
`destroy?`).

---

## 3. Finder — `app/finders/reminder_finder.rb`

O coração dos filtros da tela "Lembretes" (task 20) e da seção embutida (task 21).

```ruby
class ReminderFinder
  pattr_initialize [:user!, :account!, :params!]

  def perform
    scope = visible_reminders
    scope = apply_status_filter(scope)
    scope = apply_remindable_filter(scope)
    scope = apply_assignee_filter(scope)
    scope = apply_date_filter(scope)
    scope.order(due_at: :asc)
  end

  private

  def visible_reminders
    return account.reminders if user.administrator?

    account.reminders.where(
      'created_by_id = :uid OR assignee_id = :uid OR id IN (:general_ids)',
      uid: user.id, general_ids: general_reminder_ids_for_user
    )
  end

  # Lembretes SEM assignee cujo remindable o usuário já tem acesso
  # (pipeline member / inbox member / team member), ou lembretes
  # gerais sobre Contact (visíveis a qualquer agente da conta).
  def general_reminder_ids_for_user
    candidates = account.reminders.where(assignee_id: nil)

    pipeline_ids = user.assigned_pipelines.pluck(:id)
    inbox_ids = user.assigned_inboxes.pluck(:id)
    team_ids = user.teams.pluck(:id)

    candidates.where(
      "(remindable_type = 'PipelineItem' AND remindable_id IN (
          SELECT pipeline_items.id FROM pipeline_items
          INNER JOIN pipeline_stages ON pipeline_stages.id = pipeline_items.pipeline_stage_id
          WHERE pipeline_stages.pipeline_id IN (?)
        ))
        OR (remindable_type = 'Conversation' AND remindable_id IN (
          SELECT conversations.id FROM conversations
          WHERE conversations.inbox_id IN (?) OR conversations.team_id IN (?)
        ))
        OR remindable_type = 'Contact'
        OR (remindable_type IS NULL AND team_id IN (?))",
      pipeline_ids, inbox_ids, team_ids, team_ids
    ).pluck(:id)
  end

  def apply_status_filter(scope)
    case params[:status]
    when 'pending' then scope.pending
    when 'overdue' then scope.overdue
    when 'completed' then scope.completed
    else scope
    end
  end

  def apply_remindable_filter(scope)
    return scope if params[:remindable_type].blank?

    scope = scope.where(remindable_type: params[:remindable_type])
    scope = scope.where(remindable_id: params[:remindable_id]) if params[:remindable_id].present?
    scope
  end

  def apply_assignee_filter(scope)
    return scope if params[:assignee_id].blank?

    scope.where(assignee_id: params[:assignee_id])
  end

  def apply_date_filter(scope)
    return scope unless params[:from].present? || params[:to].present?

    scope.where(due_at: params[:from]..params[:to])
  end
end
```

**Ponto de atenção de performance** (marcar para revisão de PR, não bloqueante pro MVP):
`general_reminder_ids_for_user` monta uma query SQL bruta com subqueries pra evitar N+1 chamando o
`Reminders::RecipientsResolver` por lembrete candidato. Se o volume de lembretes crescer muito por
conta, considerar materializar essa lógica de forma diferente (ex.: view materializada ou
desnormalizar audiência numa tabela `reminder_recipients` — fora do escopo desta v1).

`user.assigned_pipelines` e `user.assigned_inboxes` já existem (implementados nas tasks 08 do
Kanban e no core do Chatwoot, respectivamente) — reaproveitar, não duplicar.

---

## 4. Views Jbuilder

### `app/views/api/v1/models/_reminder.json.jbuilder`

```jbuilder
json.id resource.id
json.title resource.title
json.description resource.description
json.due_at resource.due_at
json.status resource.status
json.notified_at resource.notified_at
json.completed_at resource.completed_at
json.created_at resource.created_at
json.assignee resource.assignee, partial: 'api/v1/models/agent', as: :resource if resource.assignee
json.team resource.team, partial: 'api/v1/models/team', as: :resource if resource.team
json.created_by resource.created_by, partial: 'api/v1/models/agent', as: :resource
if resource.remindable.present?
  json.remindable do
    json.id resource.remindable.id
    json.type resource.remindable_type
    json.label remindable_label(resource.remindable)
  end
end
```

`remindable_label` (helper simples, pode ir em `app/helpers/reminders_helper.rb` ou inline no
jbuilder via `content_tag`-free lambda): retorna `resource.remindable.title` (PipelineItem/oportunidade),
`resource.remindable.name` (Contact), ou `"##{resource.remindable.display_id}"` (Conversation) —
qualquer atributo amigável já exposto por esses models, sem inventar um método novo neles.

### `app/views/api/v1/accounts/reminders/index.json.jbuilder`
```jbuilder
json.array! @reminders do |reminder|
  json.partial! 'api/v1/models/reminder', formats: [:json], resource: reminder
end
```

`show.json.jbuilder`, `create.json.jbuilder`, `update.json.jbuilder`, `complete.json.jbuilder` —
todos delegam ao partial (`json.partial! 'api/v1/models/reminder', formats: [:json], resource: @reminder`),
mesmo padrão de `pipeline_items`.

---

## 5. Specs

`spec/finders/reminder_finder_spec.rb` — cobrir os mesmos 8 cenários de audiência da task 17, mas
verificando visibilidade de *listagem* em vez de destinatário de notificação (ex: agente que é
membro de um pipeline vê lembretes gerais daquele pipeline na sua listagem, mesmo sem ser o
assignee).

`spec/controllers/api/v1/accounts/reminders_controller_spec.rb` (confirmar se specs de controller
recentes ficam em `spec/controllers` ou `spec/requests` olhando `pipeline_items_controller_spec.rb`
antes de criar, e seguir a mesma convenção) — cobrir CRUD completo, `complete`, e as regras de
autorização da `ReminderPolicy` (criador/assignee/admin).

---

## Verificação

```bash
# Criar lembrete vinculado a uma oportunidade
curl -X POST /api/v1/accounts/1/reminders \
  -d '{"reminder": {"title": "Follow-up", "due_at": "2026-07-05T14:00:00Z", "remindable_type": "PipelineItem", "remindable_id": 5}}'

# Listar só os vencidos
curl -X GET "/api/v1/accounts/1/reminders?status=overdue"

# Listar os de uma oportunidade específica
curl -X GET "/api/v1/accounts/1/reminders?remindable_type=PipelineItem&remindable_id=5"

# Marcar como concluído
curl -X POST /api/v1/accounts/1/reminders/10/complete

# Tentar excluir como agente que não é criador nem admin — deve dar 403
curl -X DELETE /api/v1/accounts/1/reminders/10 -H "api_access_token: TOKEN_AGENTE_QUALQUER"
```

Confirmar: agente vê na listagem os lembretes que criou, os que lhe foram atribuídos, e os gerais
de registros aos quais tem acesso — nada além disso. Admin vê tudo da conta.
