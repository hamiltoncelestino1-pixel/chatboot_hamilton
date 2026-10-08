# Task 04 — Fix: `overdue_tasks_count` sempre 0 fora do board Kanban e corrompe cache Vuex

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/controllers/api/v1/accounts/pipeline_items_controller.rb`:

```ruby
def index                                              # linha 10
  return nested_pipeline_index if params[:pipeline_id].present?

  items = policy_scope(
    Current.account.pipeline_items
           .where(pipeline_id: policy_scope(Current.account.pipelines).select(:id))
           .includes(:contact, :conversation, :assignee, :team, :pipeline_lost_reason, pipeline_stage: :pipeline)
  )
  items = items.where(contact_id: params[:contact_id]) if params[:contact_id].present?
  items = items.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
  @items = items.order(created_at: :desc)
end
# ...
def nested_pipeline_index                              # linha 86
  @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
  @items = pipeline_items_scope
  @items = @items.where(pipeline_stage_id: params[:stage_id]) if params[:stage_id].present?
  @overdue_tasks_counts = Task.pending
                              .where(pipeline_item_id: @items.map(&:id))
                              .where('due_date < ?', Time.current)
                              .group(:pipeline_item_id).count
  render :index
end
```

Só `nested_pipeline_index` (chamada quando `params[:pipeline_id]` está presente, i.e. o board
Kanban) calcula `@overdue_tasks_counts`. A action `index` "pura" (chamada quando não há
`pipeline_id`) nunca seta essa variável — e `app/views/api/v1/models/_pipeline_item.json.jbuilder:38`
faz `local_assigns[:overdue_tasks_counts]&.fetch(resource.id, 0) || 0`, que cai sempre em `0`.

Quem bate na action `index` sem `pipeline_id`: `fetchItemsForContact`/`fetchItemsForConversation`
(`app/javascript/dashboard/store/modules/kanban/actions.js:237-247`), usadas por
`ConversationOpportunities.vue`/`ContactOpportunities.vue` — painéis abertos o tempo todo pelo
agente ao navegar entre conversas/contatos.

O problema não fica isolado nessas telas: `SET_ITEM_DATA`
(`app/javascript/dashboard/store/modules/kanban/mutations.js:119-121`) faz
`$state.items[item.id] = item` — substituição completa, no **mesmo** dicionário `items`
compartilhado com o board Kanban. Abrir uma conversa/contato vinculado a um card com tarefas
vencidas e depois voltar pro board (sem refetch completo) apaga o badge de "atrasado" daquele
card, porque o registro no store foi sobrescrito com `overdue_tasks_count: 0`.

## O que corrigir

1. Extrair o cálculo de `@overdue_tasks_counts` (`Task.pending.where(pipeline_item_id:
   ...).where('due_date < ?', Time.current).group(:pipeline_item_id).count`) para um método
   privado compartilhado, chamado tanto por `index` quanto por `nested_pipeline_index` — não
   duplicar a query, e continuar sendo **1 query agregada por listagem**, não 1 por item (não
   reintroduzir o N+1 que a auditoria de 2026-08-16 já corrigiu duas vezes nesse mesmo módulo,
   ver `claude/crm_optimizacao_tasks/02-*.md` e `03-*.md`).
2. Confirmar que a mutation `SET_ITEM_DATA` do Vuex, depois do fix, recebe sempre o valor
   correto de `overdue_tasks_count` (não `0` fixo) em qualquer contexto de fetch — o fix do
   backend já resolve o problema de raiz, mas vale revisar se a mutation deveria fazer merge
   parcial em vez de replace total como rede de segurança contra o mesmo padrão de bug
   reaparecer no futuro (mesma consideração da task 03 para o módulo de Tasks).

## Testes

Testar manualmente no Docker local: abrir um card com tarefa vencida no board Kanban
(confirmar badge visível), abrir a conversa/contato vinculado a esse card (painel de
Oportunidades), voltar pro board sem dar reload completo — o badge deve continuar visível.

## Critério de pronto

- `overdue_tasks_count` retorna o valor correto em qualquer action que serialize
  `PipelineItem` (`index`, `nested_pipeline_index`, `show`, etc.), não só no board.
- Abrir conversa/contato vinculado a um card não apaga o badge de atrasado ao voltar pro board.
- Continua sendo 1 query agregada por listagem (confirmar com `bundet exec rails console` ou
  log de query, não reintroduzir N+1).
- `bundle exec rubocop -a` limpo no arquivo tocado.
