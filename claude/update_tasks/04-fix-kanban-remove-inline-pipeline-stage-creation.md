# Task: Remover criação de Pipeline/Etapa direto no board do Kanban

## Objetivo

O board do Kanban (`/app/accounts/:id/kanban`) hoje tem um botão "Criar Pipeline" e uma
coluna/botão "Adicionar etapa" — queremos remover os dois. CRUD de pipelines e etapas passa a ser
possível **somente** pela tela de Configurações > Pipelines (já implementada na task 12).

## Diagnóstico (código atual verificado)

Confirmado via exploração direta que `AddPipelineModal.vue` é usado **exclusivamente** pelo board
do Kanban:

- `app/javascript/dashboard/routes/dashboard/kanban/pages/KanbanIndex.vue`:
  - Linhas 64-70: botão "Criar Pipeline", `@click="showCreatePipelineModal = true"`.
  - Linha 89: `<KanbanBoard @add-stage="showCreatePipelineModal = true" ...>` — clicar em
    "Adicionar etapa" hoje abre o MESMO modal de criar pipeline (UX confusa: criar etapa abre o
    fluxo inteiro de criar pipeline).
  - Linha 82: `<KanbanEmptyState @create="showCreatePipelineModal = true" ...>`.
  - Linhas 97-101: `<AddPipelineModal v-if="showCreatePipelineModal" ...>`.
- `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanBoard.vue`, linhas 72-78:
  botão "+ Adicionar etapa" que faz `emit('add-stage')`.

A página Settings > Pipelines (`app/javascript/dashboard/routes/dashboard/settings/pipelines/`) usa
componentes **totalmente independentes** (`AddPipeline.vue` para criar pipeline, `PipelineStagesSection.vue`
para gerenciar etapas) — não importa nem referencia `AddPipelineModal.vue` em nenhum lugar. Ou seja,
remover o modal do board **não afeta** Configurações.

As actions de store usadas pelo modal (`kanban/createPipeline`, `kanban/createStage`,
`kanban/reorderStages`) continuam em uso por Configurações — **não remover essas actions**, só a UI
do board que as invoca.

---

## 1. `app/javascript/dashboard/routes/dashboard/kanban/pages/KanbanIndex.vue`

Remover:
- Import de `AddPipelineModal` (linha 9).
- `const showCreatePipelineModal = ref(false);` (linha 21).
- O botão "Criar Pipeline" inteiro (linhas 64-70).
- O bloco `<AddPipelineModal v-if="showCreatePipelineModal" ... />` (linhas 97-101).
- No `<KanbanBoard>`, remover o listener `@add-stage="showCreatePipelineModal = true"` (linha 89).
- No `<KanbanEmptyState>`, trocar `@create="showCreatePipelineModal = true"` (linha 82) — ver seção 3.

## 2. `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanBoard.vue`

- Remover o botão/coluna "+ Adicionar etapa" (linhas 72-78).
- Remover `'add-stage'` de `defineEmits([...])`.

## 3. `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanEmptyState.vue`

Trocar o botão que emitia `create` por um link direto para Configurações > Pipelines:

```vue
<script setup>
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';

const { t } = useI18n();
const route = useRoute();
</script>

<template>
  <div class="flex flex-col items-center justify-center flex-1 gap-4 p-8 text-center">
    <span class="i-lucide-columns-3 size-16 text-slate-300 dark:text-slate-600" />
    <div>
      <h3 class="text-base font-semibold text-slate-700 dark:text-slate-200">
        {{ t('KANBAN.EMPTY_STATE.TITLE') }}
      </h3>
      <p class="mt-1 text-sm text-slate-500 dark:text-slate-400 max-w-xs">
        {{ t('KANBAN.EMPTY_STATE.DESCRIPTION') }}
      </p>
    </div>
    <router-link
      :to="frontendURL(`accounts/${route.params.accountId}/settings/pipelines`)"
      class="px-4 py-2 text-sm font-medium text-white bg-woot-500 rounded-lg hover:bg-woot-600 transition-colors"
    >
      {{ t('KANBAN.EMPTY_STATE.BUTTON') }}
    </router-link>
  </div>
</template>
```

(confirmar o path exato da rota de listagem de pipelines em `config/routes.rb`/rotas de settings —
provavelmente `settings/pipelines` ou `settings/pipelines/list`, igual usado por
`router.push({ name: 'pipelines_list' })` em `PipelineDetail.vue`; usar `router-link :to="{ name: 'pipelines_list' }"`
em vez de montar a URL manualmente, para ficar consistente com o resto do código.)

Remover `defineEmits(['create'])`, já que não é mais necessário.

Atualizar `KANBAN.EMPTY_STATE.BUTTON` (en/pt_BR) para refletir que agora leva a Configurações — ex.
`"Manage pipelines in Settings"` / `"Gerenciar pipelines em Configurações"`.

## 4. Excluir `app/javascript/dashboard/routes/dashboard/kanban/components/AddPipelineModal.vue`

Confirmado sem nenhum outro uso no projeto — remover o arquivo.

---

## Verificação

1. Acessar `/app/accounts/:id/kanban` com pipelines já existentes — não deve haver mais botão
   "Criar Pipeline" no header, nem coluna/botão "Adicionar etapa" no final do board.
2. Acessar o Kanban numa conta **sem nenhum pipeline** — o empty state deve mostrar um botão que
   leva para Configurações > Pipelines (não deve abrir nenhum modal).
3. Confirmar que Configurações > Pipelines continua funcionando normalmente para criar pipeline e
   adicionar/editar/excluir etapas (nenhuma regressão, já que os componentes são independentes).
4. Rodar busca por `AddPipelineModal` no projeto inteiro — não deve haver mais nenhuma referência
   além do arquivo já removido do controle de versão.
