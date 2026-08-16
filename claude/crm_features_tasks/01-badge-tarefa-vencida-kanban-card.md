# Task 01 — Badge de tarefa vencida no card do Kanban

Feature 4. Sem dependências, menor escopo do épico.

## Objetivo

Mostrar no card compacto do Kanban (`KanbanCard.vue`, o que aparece na lista/coluna do
board, não no detalhe) um badge indicando quantas tarefas vencidas (`due_date` no passado,
`completed_at` nulo) aquele `pipeline_item` tem.

## Estado atual (confirmado por leitura de código)

- `KanbanCard.vue` só recebe campos básicos do `item` (título, valor, contato, assignee,
  labels, custom attributes) — nenhum dado de tasks.
- Tasks são carregadas de forma lazy em dois níveis: `TaskList.vue`
  (`app/javascript/dashboard/components-next/Tasks/TaskList.vue`) só dispara
  `tasks/fetchForPipelineItem` no seu próprio `onMounted`, e esse componente só é montado
  quando o usuário abre o card **e** expande o accordion "Tarefas" dentro de
  `KanbanCardDetail.vue` (`AccordionItem.vue` usa `v-if="isOpen"` no slot de conteúdo).
- `PipelineItemsController#index`/`nested_pipeline_index`
  (`app/controllers/api/v1/accounts/pipeline_items_controller.rb:10-22,83-105`) e
  `app/views/api/v1/models/_pipeline_item.json.jbuilder` não expõem nenhuma contagem de
  tasks hoje.
- Não existe endpoint em lote de tasks por vários `pipeline_item_id` ao mesmo tempo —
  `TasksController#index` filtra um `pipeline_item_id` por vez.

## O que criar

**Backend**: calcular a contagem de tarefas vencidas **uma vez por request de listagem**,
não uma query por card (evitar reintroduzir o N+1 que
`claude/crm_optimizacao_tasks/03-fix-items-count-nplus1-pipelines.md` acabou de corrigir em
endpoint irmão).

1. Em `PipelineItemsController#nested_pipeline_index`/`pipeline_items_scope`
   (linhas 83-105), depois de resolver `@items`, calcular:
   ```ruby
   @overdue_tasks_counts = Task.where(pipeline_item_id: @items.map(&:id), completed_at: nil)
                                .where('due_date < ?', Time.current)
                                .group(:pipeline_item_id).count
   ```
   e disponibilizar pro jbuilder (variável de instância ou passada explicitamente).
2. `app/views/api/v1/models/_pipeline_item.json.jbuilder` — novo campo:
   ```ruby
   json.overdue_tasks_count local_assigns[:overdue_tasks_counts]&.fetch(resource.id, 0) || 0
   ```
   (usar `local_assigns` ou padrão equivalente já usado em partials do projeto que recebem
   dado extra do controller além do `resource` — conferir se há precedente antes de inventar
   a forma de passar o hash pro partial).
3. Aplicar o mesmo tratamento no `index` raiz (`pipeline_items_controller.rb:10-22`), se
   esse endpoint também alimentar alguma visualização de lista de cards (confirmar durante a
   implementação se é usado pelo board ou só por outras telas).

**Frontend**:
4. `KanbanCard.vue` — renderizar um badge (contador) quando `item.overdue_tasks_count > 0`.
   Procurar um componente de badge/pill já existente no design system do dashboard antes de
   criar um novo (ex. algo usado para labels ou contadores em outros cards/listas do
   projeto).
5. Garantir que o badge atualiza em tempo real quando uma task é criada/completada/vence —
   conferir se isso exige tocar em `applyRealtimePipelineItem`
   (`store/modules/kanban/actions.js:226-242`) ou se um simples refetch ao reabrir o board é
   aceitável para a v1 (mais simples; tempo real "perfeito" do contador pode ficar pra
   depois se o esforço for desproporcional).

## Testes

Testar manualmente no Docker local: criar um card com uma task vencida, confirmar que o
badge aparece na lista do board sem abrir o card; completar a task, confirmar que o badge
some (após refresh, se tempo real não for implementado nesta v1); confirmar que cards sem
tasks vencidas não mostram nada.

## Critério de pronto

- Badge aparece só quando `overdue_tasks_count > 0`.
- Contagem calculada em 1 query agregada por listagem, não 1 por card.
- `bundle exec rubocop -a` / `pnpm eslint:fix` limpos nos arquivos tocados.
