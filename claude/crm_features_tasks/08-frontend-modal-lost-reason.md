# Task 08 — Frontend: modal de motivo ao mover card pra `lost`

Feature 2 (parte 3 de 3). Depende da task 07.

## Objetivo

Ao mover um card pra um estágio do tipo `lost` (drag-and-drop ou edição manual), pedir o
motivo antes de confirmar o movimento.

## Estado atual (confirmado por leitura de código)

Dois pontos de entrada convergem na mesma action Vuex:
- Drag-and-drop: `KanbanColumn.vue:36-48` (`onAdd`) → `KanbanBoard.vue:38-45`
  (`handleCardMove`) → `store.dispatch('kanban/moveItem', ...)`.
- Edição manual: `KanbanCardDetail.vue:209-233` (`handleSave`), quando
  `form.value.pipeline_stage_id !== props.item.pipeline_stage_id` → mesmo dispatch.

Ambos convergem em `store/modules/kanban/actions.js:141-160` (`moveItem`), que chama
`PipelineItemsAPI.update(...)`. `moveItem` já tem rollback de UI otimista em caso de erro
de API (linhas 151-158).

## O que criar

1. Tela de configuração da lista de motivos em Configurações (CRUD da task 07 exposto na
   UI) — página simples de lista, seguindo o padrão de outra tela de configuração de lista
   por conta já existente no projeto (ex. Canned Responses).
2. Componente modal novo (não existe precedente pronto no Kanban) pedindo o motivo — select
   populado pela lista de `PipelineLostReason` da conta.
3. Em `KanbanColumn.vue` (drag-and-drop) e `KanbanCardDetail.vue` (edição manual): antes de
   despachar `moveItem`, checar se o estágio de destino tem `stage_type === 'lost'` (o
   objeto de stage já expõe `stage_type` via `push_event_data`,
   `getStagesForPipeline` getter). Se for, abrir o modal; só disparar `moveItem` depois do
   usuário confirmar o motivo.
4. `store/modules/kanban/actions.js` (`moveItem`) — aceitar um parâmetro
   `pipelineLostReasonId` opcional e incluí-lo no payload PATCH
   (`{ pipeline_item: { pipeline_stage_id, position, pipeline_lost_reason_id } }`).
5. **Rollback no drag-and-drop**: o `vuedraggable` já reordena visualmente antes do evento
   `onAdd`. Se o usuário cancelar o modal, reverter a posição do card usando o mesmo
   mecanismo de rollback que `moveItem` já tem para erro de API (linhas 151-158) — não
   deixar o card "preso" visualmente na coluna errada se o usuário cancelar.
6. i18n: chaves novas para o modal e para a tela de configuração de motivos (domínio kanban,
   dentro da exceção documentada no `CLAUDE.md` — sincronizar en + pt_BR).

## Riscos

- Testar especificamente o caminho de cancelamento do modal no drag-and-drop — é o cenário
  mais fácil de esquecer (diferente do caminho de erro de API, que já tem tratamento).

## Testes

Testar manualmente no Docker local (navegador): mover card pra `lost` via drag-and-drop,
confirmar que o modal aparece e o card só persiste a posição nova depois de escolher um
motivo; cancelar o modal e confirmar que o card volta pra posição original; repetir o
mesmo teste via edição manual do card (`KanbanCardDetail.vue`).

## Critério de pronto

- Modal aparece só quando o destino é um estágio `lost`.
- Motivo é salvo corretamente no card.
- Cancelamento do modal reverte a UI otimista corretamente nos dois fluxos (drag-and-drop e
  edição manual).
- i18n en + pt_BR sincronizados (domínio kanban).
- `pnpm eslint:fix` limpo nos arquivos tocados.
