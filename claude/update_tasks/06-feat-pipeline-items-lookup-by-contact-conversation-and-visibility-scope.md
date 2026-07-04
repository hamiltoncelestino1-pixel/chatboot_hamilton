# Task: Base — buscar oportunidades por contato/conversa + Scope de visibilidade por agente

## Objetivo

Esta task é pré-requisito das tasks 07 e 08. Ela entrega duas coisas que as próximas duas
dependem:

1. Capacidade de buscar oportunidades (`PipelineItem`) de um contato ou de uma conversa específica,
   atravessando todos os pipelines que o agente pode ver — hoje só existe listagem por etapa dentro
   de um pipeline específico.
2. Restrição de visibilidade: um agente (não-administrador) só deve ver oportunidades **órfãs**
   (sem `assignee_id`) ou **atribuídas a ele mesmo**. Administradores continuam vendo tudo.

## Diagnóstico (código atual verificado)

`config/routes.rb:284` já tem uma rota de nível de conta pra `pipeline_items`, mas sem `index`:

```ruby
resources :pipeline_items, only: [:create, :show, :update, :destroy] do
  collection { post :reorder }
  resource :labels, only: [:index, :create], module: :pipeline_items
end
```

`app/controllers/api/v1/accounts/pipeline_items_controller.rb` hoje só serve `index` pra rota
**aninhada** em pipeline (`/pipelines/:pipeline_id/pipeline_items`), filtrando só por `stage_id`:

```ruby
def index
  @items = pipeline_items_scope
  @items = @items.where(pipeline_stage_id: params[:stage_id]) if params[:stage_id].present?
end

private

def pipeline_items_scope
  @pipeline
    .pipeline_items
    .includes(:contact, :conversation, :pipeline_stage, :assignee, :team)
    .order('pipeline_stage_id, position')
end
```

`app/policies/pipeline_item_policy.rb` **não tem `Scope`** — `index?`/`show?`/`create?`/`update?`
sempre `true`. O controller usa `policy_scope(Current.account.pipelines)` só pra saber quais
pipelines o agente acessa (`fetch_pipeline`, `fetch_item`), mas dentro de um pipeline permitido,
**todos os cards aparecem pra qualquer agente do pipeline** — sem filtro por `assignee_id`.

Precedente já usado no projeto pra "admin vê tudo, agente vê subconjunto":
`app/models/user.rb:142-144`:
```ruby
def assigned_pipelines
  administrator? ? Current.account.pipelines : pipelines.where(account_id: Current.account.id)
end
```
E `app/policies/pipeline_policy.rb`:
```ruby
class Scope < ApplicationPolicy::Scope
  def resolve
    user.assigned_pipelines
  end
end
```

Checagem de admin já usada dentro do próprio `pipeline_item_policy.rb:19` (`destroy?`):
`@account_user.administrator?`.

---

## 1. Backend

### 1.1 `app/policies/pipeline_item_policy.rb`

```ruby
class PipelineItemPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if @account_user.administrator?

      scope.where(assignee_id: [nil, @user.id])
    end
  end

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

### 1.2 `app/controllers/api/v1/accounts/pipeline_items_controller.rb`

- `pipeline_items_scope` (index aninhado, usado pelo board) — aplicar `policy_scope`:

```ruby
def pipeline_items_scope
  policy_scope(
    @pipeline.pipeline_items
             .includes(:contact, :conversation, :pipeline_stage, :assignee, :team)
  ).order('pipeline_stage_id, position')
end
```

- `fetch_item` — aplicar `policy_scope` também na busca de um item individual (hoje só filtra por
  pipeline permitido, não por card/assignee):

```ruby
def fetch_item
  allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
  @item = policy_scope(
    Current.account.pipeline_items
           .joins(:pipeline_stage)
           .where(pipeline_stages: { pipeline_id: allowed_pipeline_ids })
  ).find(params[:id])
end
```

- `reorder` — aplicar a mesma proteção na busca de itens da etapa reordenada, pra impedir um agente
  de reordenar (movendo pra dentro do seu grupo visível) um card atribuído a outro agente:

```ruby
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
```

- Novo `index` de nível de conta (rota não aninhada, sem `pipeline_id` na URL) — filtra por
  `contact_id`/`conversation_id`, atravessando todos os pipelines visíveis ao agente:

```ruby
def index
  return nested_pipeline_index if params[:pipeline_id].present?

  items = policy_scope(
    Current.account.pipeline_items
           .joins(:pipeline_stage)
           .where(pipeline_stage: { pipeline_id: policy_scope(Current.account.pipelines).select(:id) })
           .includes(:contact, :conversation, :pipeline_stage, :assignee, :team)
  )
  items = items.where(contact_id: params[:contact_id]) if params[:contact_id].present?
  items = items.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
  @items = items.order(created_at: :desc)
end

private

def nested_pipeline_index
  fetch_pipeline
  @items = pipeline_items_scope
  @items = @items.where(pipeline_stage_id: params[:stage_id]) if params[:stage_id].present?
end
```

**Nota**: como a rota aninhada (`/pipelines/:pipeline_id/pipeline_items`) e a nova rota de conta
(`/pipeline_items`) mapeiam pro mesmo controller/action, usar `params[:pipeline_id].present?` pra
distinguir os dois casos é a forma mais simples — mas **confirmar durante a implementação** se o
`before_action :fetch_pipeline, only: [:index]` atual (linha 2) precisa ser removido do `before_action`
e chamado manualmente dentro do branch `nested_pipeline_index`, já que agora `index` também serve a
rota sem `pipeline_id`.

### 1.3 `config/routes.rb:284`

```ruby
resources :pipeline_items, only: [:index, :create, :show, :update, :destroy] do
  collection { post :reorder }
  resource :labels, only: [:index, :create], module: :pipeline_items
end
```

### 1.4 View JSON

Confirmar o jbuilder usado pelo `index`/`show` de `PipelineItem` (provavelmente
`app/views/api/v1/models/_pipeline_item.json.jbuilder`, reaproveitado por ambas as actions) e
garantir que exponha `pipeline_stage.pipeline_id` e `pipeline_stage.pipeline.name` (ou um atalho
direto `pipeline_id`/`pipeline_name` no nível raiz do item) — necessário pras tasks 07/08
construírem o link "ver no pipeline". Adicionar caso não exista:

```ruby
json.pipeline_id resource.pipeline_stage.pipeline_id
json.pipeline_name resource.pipeline_stage.pipeline.name
```

---

## 2. Frontend

### 2.1 `app/javascript/dashboard/api/pipelineItems.js`

Adicionar métodos (mantendo os já existentes):

```javascript
getByContact(contactId) {
  return axios.get(this.url, { params: { contact_id: contactId } });
}

getByConversation(conversationId) {
  return axios.get(this.url, { params: { conversation_id: conversationId } });
}
```

### 2.2 `app/javascript/dashboard/store/modules/kanban/actions.js`

```javascript
fetchItemsForContact: async ({ commit }, contactId) => {
  const { data } = await PipelineItemsAPI.getByContact(contactId);
  data.forEach(item => commit('SET_ITEM', item));
  return data;
},

fetchItemsForConversation: async ({ commit }, conversationId) => {
  const { data } = await PipelineItemsAPI.getByConversation(conversationId);
  data.forEach(item => commit('SET_ITEM', item));
  return data;
},
```

(reaproveita a mutation `SET_ITEM` já existente — guarda em `state.items`, mesmo lugar usado pelo
board; sem necessidade de um slice de state novo.)

### 2.3 `app/javascript/dashboard/store/modules/kanban/getters.js`

```javascript
getItemsForContact: $state => contactId =>
  Object.values($state.items).filter(i => i.contact?.id === contactId),

getItemsForConversation: $state => conversationId =>
  Object.values($state.items).filter(i => i.conversation?.id === conversationId),
```

---

## Verificação

1. Logar como agente não-administrador, membro de um pipeline com cards atribuídos a outros
   agentes — no board, só devem aparecer cards órfãos ou atribuídos a ele mesmo. Os contadores por
   coluna devem refletir só o que é visível (nenhuma mudança de frontend necessária pra isso, já
   confirmado que `KanbanColumn.vue` usa `localItems.length`).
2. Logar como administrador — todos os cards do pipeline devem aparecer, sem filtro.
3. Tentar (via request direto) buscar/editar/reordenar um card atribuído a outro agente, logado
   como agente comum — deve falhar (404/`RecordNotFound` via `policy_scope` + `find`) em vez de
   permitir.
4. `GET /api/v1/accounts/:id/pipeline_items?contact_id=X` — deve retornar as oportunidades desse
   contato em todos os pipelines visíveis ao usuário autenticado, respeitando a mesma regra de
   visibilidade (agente só vê órfãs/próprias, mesmo aqui).
5. `GET /api/v1/accounts/:id/pipeline_items?conversation_id=Y` — mesma verificação, filtrando por
   conversa.
6. Confirmar que a rota aninhada (`/pipelines/:pipeline_id/pipeline_items?stage_id=Z`, usada pelo
   board) continua funcionando exatamente como antes, sem regressão.
