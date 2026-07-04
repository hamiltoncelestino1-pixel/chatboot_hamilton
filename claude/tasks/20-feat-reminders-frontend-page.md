# Task: Sistema de Lembretes — Frontend: Tela "Lembretes" Standalone

## Objetivo

Criar a página principal de Lembretes: um item de navegação de nível principal (irmão do "Kanban",
não dentro de Configurações), com lista de todos os lembretes visíveis pro usuário atual, filtros
por status e data, e link pro registro vinculado quando houver.

**Pré-requisito:** task 19 implementada (store `reminders` disponível).

---

## 1. Rota — `app/javascript/dashboard/routes/dashboard/reminders/routes.js`

Mirror exato de `app/javascript/dashboard/routes/dashboard/kanban/routes.js` (export nomeado
`routes`, não `export default { routes }` — esse último é o padrão usado só pelos módulos dentro de
Configurações):

```javascript
import { frontendURL } from 'dashboard/helper/URLHelper';

const RemindersIndex = () => import('./pages/RemindersIndex.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/reminders'),
    name: 'reminders_index',
    component: RemindersIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
```

### Registrar em `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`

Mesmo padrão já usado pro Kanban (confirmado por leitura direta do arquivo):

```javascript
import { routes as remindersRoutes } from './reminders/routes';
// ...
const routes = [
  // ...
  ...kanbanRoutes,
  ...remindersRoutes,
];
```

---

## 2. Sidebar — `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

Item irmão de "Kanban" (linha ~464-470 atual), mesmo formato exato:

```javascript
{
  name: 'Kanban',
  label: t('SIDEBAR.KANBAN'),
  icon: 'i-lucide-columns-3',
  to: accountScopedRoute('kanban_index'),
  activeOn: ['kanban_index'],
},
{
  name: 'Reminders',
  label: t('SIDEBAR.REMINDERS'),
  icon: 'i-lucide-bell-ring',
  to: accountScopedRoute('reminders_index'),
  activeOn: ['reminders_index'],
},
```

---

## 3. Página — `app/javascript/dashboard/routes/dashboard/reminders/pages/RemindersIndex.vue`

```vue
<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import RemindersTable from '../components/RemindersTable.vue';
import ReminderFormModal from 'dashboard/components-next/Reminders/ReminderFormModal.vue';

const { t } = useI18n();
const store = useStore();
const reminders = useMapGetter('reminders/getReminders');
const uiFlags = useMapGetter('reminders/getUIFlags');

const activeStatus = ref('pending'); // pending | overdue | completed | all
const showFormModal = ref(false);

const fetchReminders = () => {
  const status = activeStatus.value === 'all' ? undefined : activeStatus.value;
  store.dispatch('reminders/get', { status });
};

watch(activeStatus, fetchReminders);
onMounted(fetchReminders);

const statusTabs = computed(() => [
  { key: 'pending', label: t('REMINDERS.STATUS.PENDING') },
  { key: 'overdue', label: t('REMINDERS.STATUS.OVERDUE') },
  { key: 'completed', label: t('REMINDERS.STATUS.COMPLETED') },
  { key: 'all', label: t('REMINDERS.STATUS.ALL') },
]);
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex items-center justify-between px-4 py-3 border-b border-slate-100 dark:border-slate-800">
      <h1 class="text-base font-semibold">{{ t('REMINDERS.TITLE') }}</h1>
      <button
        class="px-3 py-1.5 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg"
        @click="showFormModal = true"
      >
        {{ t('REMINDERS.ADD') }}
      </button>
    </div>

    <div class="flex gap-2 px-4 py-2 border-b border-slate-100 dark:border-slate-800">
      <button
        v-for="tab in statusTabs"
        :key="tab.key"
        class="px-3 py-1 text-xs font-medium rounded-full"
        :class="activeStatus === tab.key ? 'bg-woot-500 text-white' : 'bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300'"
        @click="activeStatus = tab.key"
      >
        {{ tab.label }}
      </button>
    </div>

    <RemindersTable :reminders="reminders" :is-loading="uiFlags.isFetching" />

    <ReminderFormModal v-if="showFormModal" @close="showFormModal = false" />
  </div>
</template>
```

---

## 4. `app/javascript/dashboard/routes/dashboard/reminders/components/RemindersTable.vue`

Tabela dedicada (colunas diferentes de qualquer tabela genérica já existente): título, vencimento
(formatado via `dynamicTime`, mesmo helper já usado em `NotificationTable.vue`), vinculado a
(`remindable.label` + ícone por tipo), atribuído a (avatar do `assignee`, ou "Geral" se ausente —
chave `KANBAN.ITEM.UNASSIGNED`-like, criar `REMINDERS.GENERAL`), status (badge colorido:
pendente/vencido/concluído), ações (marcar concluído / editar / excluir, gated por
`created_by`/`assignee`/admin — mesma regra da `ReminderPolicy`, refletida no frontend checando
`reminder.created_by.id === currentUserId || reminder.assignee?.id === currentUserId ||
isAdmin`).

Clique na linha, quando `reminder.remindable` presente, navega:

```javascript
const goToRemindable = reminder => {
  if (!reminder.remindable) return;
  const { type, id } = reminder.remindable;
  if (type === 'Conversation') {
    router.push({ name: 'conversation_through_inbox', params: { conversation_id: id } }); // confirmar nome exato da rota de conversa
  } else if (type === 'Contact') {
    router.push({ name: 'contacts_edit', params: { contactId: id } });
  } else if (type === 'PipelineItem') {
    router.push({ name: 'kanban_index' }); // Kanban não suporta deep-link por card hoje — abre o board
  }
};
```

(Confirmar o nome exato da rota de conversa antes de implementar — buscar em
`app/javascript/dashboard/routes/dashboard/conversation/conversation.routes.js` ou equivalente.)

Botão de concluir inline dispara `store.dispatch('reminders/complete', reminder.id)` sem navegar.

---

## 5. i18n

`app/javascript/dashboard/i18n/locale/en/reminder.json` (arquivo novo, mirror de `kanban.json`):

```json
{
  "REMINDERS": {
    "TITLE": "Reminders",
    "ADD": "New reminder",
    "GENERAL": "General",
    "STATUS": {
      "PENDING": "Pending",
      "OVERDUE": "Overdue",
      "COMPLETED": "Completed",
      "ALL": "All"
    },
    "TABLE": {
      "TITLE": "Title",
      "DUE_AT": "Due",
      "LINKED_TO": "Linked to",
      "ASSIGNEE": "Assignee",
      "STATUS": "Status",
      "ACTIONS": "Actions",
      "EMPTY": "No reminders found"
    },
    "API": {
      "COMPLETE_SUCCESS": "Reminder marked as completed.",
      "DELETE_SUCCESS": "Reminder deleted successfully.",
      "ERROR": "Something went wrong. Please try again."
    }
  }
}
```

`app/javascript/dashboard/i18n/locale/pt_BR/reminder.json` — traduzir integralmente (`"TITLE":
"Lembretes"`, `"ADD": "Novo lembrete"`, `"GENERAL": "Geral"`, `"PENDING": "Pendente"`, `"OVERDUE":
"Vencido"`, `"COMPLETED": "Concluído"`, `"ALL": "Todos"`, etc).

Registrar `reminder.json` no índice de merge de locales — localizar o arquivo que já importa
`kanban.json` (provavelmente `app/javascript/dashboard/i18n/locale/en/index.js`) e replicar.

`SIDEBAR.REMINDERS`: `"Reminders"` (en) / `"Lembretes"` (pt_BR).

`NOTIFICATIONS_PAGE.TYPE_LABEL.reminder_due`: `"Reminder"` (en) / `"Lembrete"` (pt_BR) — única
chave necessária pra página de Notificações genérica (`NotificationTable.vue`) já reconhecer o novo
tipo, sem nenhuma mudança de componente.

---

## Verificação

1. Navegar para `/accounts/:id/reminders` — item "Lembretes" aparece na sidebar principal, irmão
   do "Kanban".
2. Criar um lembrete solto pelo botão "Novo lembrete" — aparece na aba "Pendente".
3. Trocar pra aba "Vencido" — só lembretes com `due_at` no passado e não concluídos aparecem.
4. Marcar um lembrete como concluído — some da aba "Pendente"/"Vencido", aparece em "Concluído".
5. Lembrete vinculado a uma conversa/contato/oportunidade — clicar na linha navega pro registro.
6. Testar como agente sem acesso a determinado pipeline/inbox — não vê lembretes gerais desses
   registros (mas vê os que criou ou que lhe foram atribuídos).
