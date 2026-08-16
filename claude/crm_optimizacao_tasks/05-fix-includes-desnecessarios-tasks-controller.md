# Task 05 — Fix: `includes` de associações nunca usadas em `TasksController#index`

Severidade: 🟠 Alta. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`app/controllers/api/v1/accounts/tasks_controller.rb:6`:

```ruby
def index
  items = policy_scope(Current.account.tasks.includes(:contact, :conversation, :pipeline_item, :assignee))
  ...
end
```

Faz eager load de `:contact`, `:conversation`, `:pipeline_item` e `:assignee` — mas
`app/views/api/v1/models/_task.json.jbuilder:1-10` só serializa:

```ruby
json.id resource.id
json.title resource.title
json.due_date resource.due_date.to_i
json.completed_at resource.completed_at&.to_i
json.contact_id resource.contact_id
json.conversation_id resource.conversation_id
json.pipeline_item_id resource.pipeline_item_id
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
json.assignee resource.assignee, partial: 'api/v1/models/agent', as: :resource
```

Ou seja, `contact_id`/`conversation_id`/`pipeline_item_id` são lidos como colunas cruas (sem
tocar no objeto associado) — só `resource.assignee` de fato acessa uma associação carregada.
`includes(:contact, :conversation, :pipeline_item)` faz 3 preloads que nunca são usados,
desperdiçando 3 queries (ou joins) por listagem de tasks sem nenhum ganho.

## O que corrigir

Reduzir para:

```ruby
items = policy_scope(Current.account.tasks.includes(:assignee))
```

Antes de aplicar, confirmar que nenhum outro método do controller (`show`, `create`,
`update`, `complete`) depende desses preloads via `@task` — `fetch_task`
(`tasks_controller.rb:42-44`) usa `policy_scope(Current.account.tasks).find(params[:id])`
sem `includes`, então é um método separado, não afetado por esta mudança.

## Testes

Testar manualmente: listar tasks de um contato/conversa/pipeline item com Docker local
rodando, confirmar que a resposta JSON continua idêntica (mesmos campos, mesmos valores).

## Critério de pronto

- `TasksController#index` só faz `includes(:assignee)`.
- Resposta JSON de `GET /tasks` inalterada.
- `bundle exec rubocop -a` limpo no arquivo tocado.
