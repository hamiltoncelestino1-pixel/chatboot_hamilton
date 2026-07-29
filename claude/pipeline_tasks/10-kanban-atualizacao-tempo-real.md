# Task 10 — Kanban: atualização em tempo real (ActionCable)

Parte do Grupo D ([visão geral](00-visao-geral.md)). Recomenda-se fazer por último — depende
conceitualmente da task 09 (é o cenário que mais evidencia a necessidade: uma automação move
um card enquanto outro usuário está com o board aberto) e é o subtask de **maior incerteza de
esforço de todo o plano**.

## Objetivo

Hoje o Kanban não atualiza sozinho quando outro processo (automação, macro, ou outro agente)
cria ou move um card — precisa de refresh manual. Isso fica mais evidente a partir das tasks
04/06/09, onde ações passam a criar/mover cards em segundo plano (job de automação, macro em
background).

## 1. Antes de estimar: localizar o padrão de broadcast já usado

Buscar no código como `Conversation`/`Message` fazem broadcast em tempo real hoje (canal
ActionCable, broadcaster, e onde no model o broadcast é disparado — provavelmente um
concern/callback específico). **Esta etapa de investigação deve vir antes de qualquer
estimativa de prazo** — o esforço real desta task depende inteiramente de quão reaproveitável
esse mecanismo existente é para `PipelineItem`.

## 2. Broadcast de `PipelineItem`

Depois da investigação acima, criar o mirror equivalente para `PipelineItem`:
- Broadcast em `after_create` e em `after_update` (quando `pipeline_stage_id`, `assignee_id`
  ou `team_id` mudam — os campos que afetam a posição/aparência do card no board).
- Canal escopado por conta/pipeline, seguindo o mesmo padrão de escopo já usado pelos canais
  existentes (por conta, ou por conta+recurso).

## 3. Frontend — consumir o broadcast

- Novo listener de ActionCable no Kanban (`KanbanBoard.vue` ou um novo composable
  `useKanbanRealtime.js`), inscrevendo no canal criado acima.
- `store/modules/kanban/` — nova mutation/action para aplicar a atualização recebida (criar
  item novo na coluna certa, mover item existente de coluna, atualizar campos), reaproveitando
  as mutations já existentes (`mutations.js`) sempre que possível em vez de criar um caminho
  paralelo de atualização de estado.

## Testes / QA

- QA manual: com o Kanban aberto em duas abas/sessões, disparar uma automação/macro que move
  um card (tasks 04/06/09) e confirmar que a outra aba atualiza sem F5.
- Testes automatizados de ActionCable, se o padrão já usado pelo projeto para
  `Conversation`/`Message` tiver testes equivalentes — mirror desses specs.

## Critério de pronto

- Esforço real estimado após a investigação do item 1 (pode revelar que é mais simples ou
  mais complexo do que este documento assume).
- Board atualiza em tempo real para criação e movimentação de cards, confirmado com QA manual
  de duas sessões simultâneas.

## Observação

Se a investigação do item 1 revelar que o mecanismo de broadcast existente não é facilmente
reaproveitável (ex. acoplado fortemente a `Conversation`), considerar entregar esta task como
"refresh automático por polling leve" (ex. refetch periódico da coluna ativa) como alternativa
de menor esforço, e documentar a troca explicitamente antes de implementar — não é uma
decisão para tomar sozinho sem alinhar com quem aprovou o plano original.
