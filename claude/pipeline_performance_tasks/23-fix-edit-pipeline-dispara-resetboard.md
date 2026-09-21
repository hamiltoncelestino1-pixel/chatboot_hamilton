# Task 23 — Fix: salvar configuração do pipeline refaz o fetch de todas as colunas

Severidade: 🟢 Baixa. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

O watcher que restaura filtros e recarrega o board observa o **objeto** do pipeline ativo, não o
id — `app/javascript/dashboard/routes/dashboard/kanban/pages/KanbanIndex.vue:29-45`:

```js
const activePipeline = useMapGetter('kanban/getActivePipeline');
// ...
watch(
  activePipeline,
  async pipeline => {
    if (!pipeline) return;
    const saved = kanbanBoardSettings(pipeline.id);
    store.commit('kanban/SET_KANBAN_FILTERS', saved.filters);
    // ...
    await store.dispatch('kanban/resetBoard');
  },
  { immediate: true }
);
```

`getActivePipeline` devolve `$state.pipelines[$state.activePipelineId]` (`getters.js:112-113`), e
qualquer mutation que recrie esse objeto muda a identidade que o `watch` compara:

- `EDIT_PIPELINE` (`mutations.js:62-67`) monta um objeto novo com spread — disparado por
  `updatePipeline` (`actions.js:88-99`), ou seja, **toda vez que alguém salva uma configuração do
  pipeline** (nome, atribuição automática, `stale_alert_days`, etc.);
- `SET_PIPELINES` (`mutations.js:32-47`) substitui o dicionário inteiro (`$state.pipelines = records`),
  então qualquer `fetchPipelines` posterior ao primeiro também dispara.

Efeito: um `resetBoard` inteiro — uma requisição por coluna, todas resetadas para a página 1 —
quando nada que afete a listagem mudou. Se o agente tinha rolado até a página 4 de uma coluna,
perde a rolagem.

Não é grave (o board fica correto, só faz trabalho à toa), mas é exatamente o tipo de request
desnecessário que o épico se propôs a eliminar, e piora justamente em contas grandes.

## O que corrigir

1. Observar o **id**, não o objeto: `watch(() => activePipeline.value?.id, ...)`. O corpo do
   watcher só usa `pipeline.id` de fato (para `kanbanBoardSettings` e `pipelineMembers/get`), então
   a mudança é direta.
2. Confirmar que o `{ immediate: true }` continua funcionando para o fluxo de mount: em
   `KanbanIndex.vue:64-69` o `SET_ACTIVE_PIPELINE` é commitado depois do `fetchPipelines`, e é ele
   que faz o watcher disparar pela primeira vez — trocar para o id não pode quebrar isso.
3. Conferir se `EDIT_PIPELINE` precisa mesmo recriar o objeto. Se o único consumidor sensível era
   este watcher, a mudança no watcher basta; não vale mexer na mutation só por isso.
4. Enquanto estiver no arquivo: confirmar que trocar de pipeline continua **sim** disparando o
   reset (é o comportamento desejado, e o comentário de `PipelineSelector.vue:13-16` depende
   disso — ele deliberadamente não despacha nada, contando com este watcher).

## Testes

1. Board aberto, rolar uma coluna até carregar 2-3 páginas. Abrir Configurações → Pipelines,
   salvar uma alteração qualquer no pipeline ativo, voltar ao board: **não** deve haver uma
   rajada de requests na aba Network, e a rolagem/páginas carregadas devem continuar.
2. Trocar de pipeline no `PipelineSelector`: continua resetando e buscando a página 1 de cada
   coluna, com os filtros salvos daquele pipeline aplicados.
3. Recarregar a página do board: carga inicial acontece uma vez só (contar os requests de
   `pipeline_items` na aba Network — deve ser exatamente um por stage).
4. Mudar filtro e ordenação: continuam disparando `resetBoard` normalmente.

## Critério de pronto

- Salvar configuração do pipeline não redispara o fetch das colunas.
- Troca de pipeline, carga inicial e mudança de filtro/sort continuam funcionando, com um request
  por coluna cada.
- `pnpm eslint` limpo.

## Resultado (2026-09-18)

`KanbanIndex.vue`: `watch(activePipeline, ...)` → `watch(() => activePipeline.value?.id, ...)`.
Corpo do watcher ajustado para usar o `pipelineId` recebido diretamente em vez de `pipeline.id`.
Não mexi em `EDIT_PIPELINE` — conferi todos os outros consumidores de `getActivePipeline`
(`AddItemModal`, `KanbanBoard`, `KanbanCardDetail`, `KanbanFilterBar`, `KanbanSortMenu`,
`PipelineSelector`) e nenhum outro `watch()` depende da identidade do objeto, só deste arquivo.

`pnpm eslint`: 0 erros.

Validado na aplicação real rodando (não só leitura de código), via `store.dispatch`/`commit`
diretos:
1. Chamei `store.dispatch('kanban/updatePipeline', { id: 2308, name: <mesmo>, description:
   'task23 test save' })` — update real, salvo no banco (`EDIT_PIPELINE` recriou o objeto,
   confirmado por `before !== after`). **Nenhuma request nova de `pipeline_items` disparou**
   (4 antes, 4 depois, mesmas da carga inicial).
2. Troquei de pipeline via `SET_ACTIVE_PIPELINE` (o mesmo commit que `PipelineSelector.vue`
   faz) — **3 requests novas** saíram, uma por stage do pipeline novo. O reset continua
   funcionando na troca de verdade.

Descrição de teste revertida no banco depois.
