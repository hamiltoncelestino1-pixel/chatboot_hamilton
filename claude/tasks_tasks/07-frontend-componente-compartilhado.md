# Task 07 — Frontend: componentes `Tasks/` compartilhados

Parte do Grupo B ([visão geral](00-visao-geral.md)). Depende da [06](06-frontend-api-store-realtime.md).

## Objetivo

Um único conjunto de componentes em `components-next/Tasks/`, reutilizado pelos 3 pontos de
entrada (tasks 08-10) via props — evita duplicar a lista/formulário de tarefas em 3 lugares.
`<script setup>` + props/emits em runtime, como todo componente novo em `components-next/`
(`AGENTS.md`).

## 1. `components-next/Tasks/TaskList.vue`

Mirror direto de `ConversationOpportunities.vue`/`ContactOpportunities.vue` (mesmo shape:
loading state, empty state com CTA, lista, botão "+ criar"). Aceita **um dos três** IDs de
contexto (o componente pai decide qual store action disparar):

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import TaskItem from './TaskItem.vue';
import TaskFormModal from './TaskFormModal.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
  pipelineItemId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const store = useStore();
const isFetching = ref(true);
const showFormModal = ref(false);

const fetchAction = props.pipelineItemId
  ? 'tasks/fetchForPipelineItem'
  : props.conversationId
    ? 'tasks/fetchForConversation'
    : 'tasks/fetchForContact';
const fetchId = props.pipelineItemId || props.conversationId || props.contactId;

const getterName = props.pipelineItemId
  ? 'tasks/getTasksForPipelineItem'
  : props.conversationId
    ? 'tasks/getTasksForConversation'
    : 'tasks/getTasksForContact';
const tasksGetter = useMapGetter(getterName);
const tasks = computed(() =>
  [...tasksGetter.value(Number(fetchId))].sort((a, b) => a.due_date - b.due_date)
);

onMounted(async () => {
  try {
    await store.dispatch(fetchAction, fetchId);
  } finally {
    isFetching.value = false;
  }
});
</script>

<template>
  <div class="px-4 py-3">
    <div v-if="isFetching" class="flex justify-center py-4">
      <span class="i-lucide-loader size-5 animate-spin text-slate-400" />
    </div>
    <template v-else>
      <div v-if="!tasks.length" class="text-center py-3">
        <p class="text-sm text-n-slate-11 mb-3">
          {{ t('TASKS.EMPTY_STATE') }}
        </p>
        <button
          class="px-3 py-1.5 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
          @click="showFormModal = true"
        >
          {{ t('TASKS.CREATE') }}
        </button>
      </div>
      <div v-else class="space-y-2">
        <TaskItem
          v-for="task in tasks"
          :key="task.id"
          :task="task"
        />
        <button
          class="text-sm text-woot-500 hover:text-woot-600 font-medium transition-colors"
          @click="showFormModal = true"
        >
          + {{ t('TASKS.CREATE') }}
        </button>
      </div>
    </template>

    <TaskFormModal
      v-if="showFormModal"
      :contact-id="contactId"
      :conversation-id="conversationId"
      :pipeline-item-id="pipelineItemId"
      @close="showFormModal = false"
    />
  </div>
</template>
```

## 2. `components-next/Tasks/TaskItem.vue`

Linha de tarefa: título, data/hora formatada (usar o helper de data já usado no projeto — ver
`dashboard/helper/date-helper.js` antes de reinventar formatação), avatar do assignee
(componente `Avatar` já existente em `components-next/avatar/`), badge de "vencida" se
`due_date < now && !completed_at`, checkbox/botão de concluir chamando
`store.dispatch('tasks/complete', task.id)`, e um botão de excluir (`store.dispatch('tasks/delete', task.id)`,
visível conforme `TaskPolicy#destroy?` — replicar no frontend a mesma regra: assignee atual ou
admin, usando o getter de usuário atual já usado em outros componentes de ação restrita, ex.
`useMapGetter('getCurrentUser')`).

## 3. `components-next/Tasks/TaskFormModal.vue`

Modal de criar/editar — mirror de `AddItemModal.vue`
(`routes/dashboard/kanban/components/AddItemModal.vue`, usado por `ConversationOpportunities`/
`ContactOpportunities`) na estrutura (Dialog/Modal + form + submit), mas com campos: `title`
(input texto), `due_date` (date+time picker — conferir se já existe um componentee de
date+time picker combinado no projeto antes de montar dois campos separados; procurar por
`DatePicker`/`vue-datepicker` em `components-next/` ou `components/`), `assignee_id` (select de
usuários da conta, reaproveitar o componente de seleção de assignee já usado no Kanban —
`KanbanCardDetail.vue` tem um, ver como ele busca a lista de usuários elegíveis).

No `submit`, monta o payload com `contact_id`/`conversation_id`/`pipeline_item_id` vindos das
props (só os que estiverem presentes) e despacha `store.dispatch('tasks/create', payload)`.
Emitir `@close` ao terminar; o componente pai (`TaskList`) não precisa refazer fetch manual —
a resposta do create já vem com o registro novo e a mutation `SET_TASK_DATA` já atualiza o
getter reativamente.

**Nota de validação de UX (risco #3 da visão geral)**: se `due_date` escolhido for mais de 3
dias no passado, mostrar um aviso inline (não bloquear o submit, só avisar) — "essa tarefa não
vai gerar notificação porque já venceu há mais de 3 dias". Evita o usuário achar que o lembrete
vai disparar quando na prática o job periódico já não pega mais esse registro.

## Testes

Só se pedirem (Vitest, `shallowMount` como padrão do projeto).

## Critério de pronto

- Os 3 componentes renderizam isoladamente via Histoire/storybook local se o projeto tiver
  (`histoire.config.ts` existe no repo — conferir se há stories parecidas em `components-next/`
  antes de decidir se vale criar uma) ou via um teste manual simples montando `TaskList` com um
  `contactId` fixo numa página de desenvolvimento.
- Criar, concluir e excluir uma tarefa funciona ponta a ponta contra a API real (`pnpm dev` +
  backend rodando).
