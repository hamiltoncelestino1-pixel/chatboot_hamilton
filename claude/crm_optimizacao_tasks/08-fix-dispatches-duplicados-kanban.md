# Task 08 — Fix: dispatches HTTP duplicados ao abrir o Kanban

Severidade: 🟡 Média. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`KanbanCardDetail.vue` é renderizado incondicionalmente dentro de `KanbanIndex.vue`
(`KanbanIndex.vue:122-126`, sem `v-if`), então fica sempre montado junto com a página do
Kanban, mesmo quando nenhum card está aberto para detalhe. Isso causa 2 pares de dispatches
HTTP duplicados toda vez que a página carrega ou o pipeline ativo muda:

1. **`pipelineMembers/get`**:
   - `KanbanIndex.vue:28-39` observa `activePipeline` (`{ immediate: true }`) e despacha
     `store.dispatch('pipelineMembers/get', { pipelineId: pipeline.id })`.
   - `KanbanCardDetail.vue:163-171` faz o mesmíssimo dispatch, observando a mesma coisa.
   - A action `pipelineMembers/get`
     (`app/javascript/dashboard/store/modules/pipelineMembers.js:25-33`) não verifica cache
     antes de chamar a API — sempre refaz o request.

2. **`attributes/get`**:
   - `KanbanIndex.vue:50-51` (`onMounted`) despacha `store.dispatch('attributes/get')`.
   - `KanbanCardDetail.vue:173-177` (`onMounted`, sempre montado) despacha `teams/get`,
     `labels/get` **e** `attributes/get` também.
   - `attributes/get` (`app/javascript/dashboard/store/modules/attributes.js:41-51`) também
     não verifica cache.

Resultado: 2 requests HTTP idênticos para `pipeline_members` e 2 para `attributes` a cada
carregamento/troca de pipeline no Kanban.

## O que corrigir

Duas abordagens possíveis, escolher a mais simples de aplicar sem quebrar o fluxo de dados
existente:

**Opção A (preferida)**: remover a duplicação na origem — deixar o dispatch de
`pipelineMembers/get` e `attributes/get` só em `KanbanIndex.vue` (o componente pai, que já
controla o ciclo de vida da página), e remover os dispatches equivalentes de
`KanbanCardDetail.vue`, já que ele é sempre filho de `KanbanIndex.vue` na mesma sessão de
página — os dados já estarão na store quando o detail precisar deles.

**Opção B**: se `KanbanCardDetail.vue` puder ser usado de forma independente em algum outro
contexto (confirmar antes de aplicar a Opção A — procurar todos os pontos onde
`KanbanCardDetail` é importado/renderizado), manter os dispatches nos dois lugares mas
adicionar uma guarda de "já carregado" nas actions (`pipelineMembers/get`,
`attributes/get`), no padrão já usado por outros módulos Vuex do projeto que fazem cache
(verificar se `store/modules/labels.js` ou `store/modules/teams.js` já tem esse padrão de
guarda antes de replicar).

## Testes

Testar manualmente no Docker local: abrir a página do Kanban com o DevTools Network aberto,
trocar de pipeline ativo, confirmar que `pipeline_members` e `attributes` são chamados 1x
cada por troca de pipeline (não 2x).

## Critério de pronto

- Requests para `pipeline_members` e `attributes` reduzidos de 2x para 1x por
  carregamento/troca de pipeline.
- Nenhuma regressão funcional: dados de membros/atributos continuam disponíveis onde eram
  usados antes (dropdown de assignee, campos customizados no card, etc.).
- `pnpm eslint:fix` limpo nos arquivos tocados.
