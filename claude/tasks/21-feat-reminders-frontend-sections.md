# Task: Sistema de Lembretes — Frontend: Seção Reutilizável + Formulário + Composição

## Objetivo

Criar um componente único de "lembretes deste registro" (`RemindersSection.vue`) e compô-lo nos 3
lugares onde faz sentido criar um lembrete vinculado: dentro de uma Conversa, de um Contato, e de
uma Oportunidade do Kanban. Mais o formulário de criar/editar lembrete, reaproveitando o mesmo
date-time picker já usado no snooze de conversa.

**Pré-requisito:** task 19 implementada (store `reminders`).

---

## 1. `app/javascript/dashboard/components-next/Reminders/RemindersSection.vue`

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ReminderFormModal from './ReminderFormModal.vue';

const props = defineProps({
  remindableType: { type: String, default: null },
  remindableId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const store = useStore();
const getRemindersByRemindable = useMapGetter('reminders/getRemindersByRemindable');

const showFormModal = ref(false);

const reminders = computed(() =>
  props.remindableType
    ? getRemindersByRemindable.value({ type: props.remindableType, id: props.remindableId })
    : []
);

onMounted(() => {
  if (props.remindableType && props.remindableId) {
    store.dispatch('reminders/get', {
      remindable_type: props.remindableType,
      remindable_id: props.remindableId,
    });
  }
});

const handleComplete = async reminder => {
  try {
    await store.dispatch('reminders/complete', reminder.id);
  } catch {
    useAlert(t('REMINDERS.API.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex items-center justify-between">
      <span class="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase">
        {{ t('REMINDERS.TITLE') }}
      </span>
      <button class="text-xs text-woot-500 hover:text-woot-600" @click="showFormModal = true">
        + {{ t('REMINDERS.ADD') }}
      </button>
    </div>

    <div v-if="!reminders.length" class="text-xs text-slate-400">
      {{ t('REMINDERS.EMPTY_STATE') }}
    </div>

    <div v-for="reminder in reminders" :key="reminder.id" class="flex items-start gap-2 text-sm">
      <input
        type="checkbox"
        :checked="reminder.status === 'completed'"
        @change="handleComplete(reminder)"
      />
      <div class="flex-1 min-w-0">
        <p
          class="truncate"
          :class="{ 'line-through text-slate-400': reminder.status === 'completed' }"
        >
          {{ reminder.title }}
        </p>
        <p
          class="text-xs"
          :class="reminder.status === 'overdue' ? 'text-red-500' : 'text-slate-400'"
        >
          {{ new Date(reminder.due_at).toLocaleString() }}
        </p>
      </div>
    </div>

    <ReminderFormModal
      v-if="showFormModal"
      :remindable-type="remindableType"
      :remindable-id="remindableId"
      @close="showFormModal = false"
    />
  </div>
</template>
```

---

## 2. `app/javascript/dashboard/components-next/Reminders/ReminderFormModal.vue`

Reaproveita **exatamente** o `DatePicker` (`vue-datepicker-next`) já usado em
`app/javascript/dashboard/components/CustomSnoozeModal.vue` (lido integralmente): `type="datetime"`,
`inline`, `disabled-date` bloqueando datas passadas.

```vue
<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import DatePicker from 'vue-datepicker-next';

const props = defineProps({
  remindableType: { type: String, default: null },
  remindableId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('reminders/getUIFlags');

const form = reactive({
  title: '',
  description: '',
  due_at: null,
  assignee_id: null,
});

const disabledDate = date => {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  return date < yesterday;
};

const handleSubmit = async () => {
  if (!form.title.trim() || !form.due_at) return;
  try {
    await store.dispatch('reminders/create', {
      title: form.title,
      description: form.description || null,
      due_at: form.due_at,
      assignee_id: form.assignee_id || null,
      remindable_type: props.remindableType,
      remindable_id: props.remindableId,
    });
    useAlert(t('REMINDERS.API.CREATE_SUCCESS'));
    emit('close');
  } catch {
    useAlert(t('REMINDERS.API.ERROR'));
  }
};
</script>

<template>
  <Teleport to="body">
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="fixed inset-0 bg-black/30" @click="emit('close')" />
      <div class="relative w-full max-w-md bg-white dark:bg-slate-800 rounded-xl shadow-xl z-10">
        <div class="flex items-center justify-between px-6 py-4 border-b border-slate-100 dark:border-slate-700">
          <h3 class="text-base font-semibold">{{ t('REMINDERS.ADD') }}</h3>
          <button @click="emit('close')"><span class="i-lucide-x size-5" /></button>
        </div>

        <div class="px-6 py-4 space-y-4">
          <div>
            <label class="block text-sm font-medium mb-1">{{ t('REMINDERS.FORM.TITLE_LABEL') }}</label>
            <input v-model="form.title" type="text" class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700" />
          </div>
          <div>
            <label class="block text-sm font-medium mb-1">{{ t('REMINDERS.FORM.DESCRIPTION_LABEL') }}</label>
            <textarea v-model="form.description" rows="2" class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700" />
          </div>
          <div>
            <label class="block text-sm font-medium mb-1">{{ t('REMINDERS.FORM.DUE_AT_LABEL') }}</label>
            <DatePicker v-model:value="form.due_at" type="datetime" inline :disabled-date="disabledDate" />
          </div>
        </div>

        <div class="flex items-center justify-end gap-2 px-6 py-4 border-t border-slate-100 dark:border-slate-700">
          <button class="px-4 py-2 text-sm text-slate-600" @click="emit('close')">
            {{ t('REMINDERS.FORM.CANCEL') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg disabled:opacity-50"
            :disabled="!form.title.trim() || !form.due_at || uiFlags.isCreating"
            @click="handleSubmit"
          >
            {{ t('REMINDERS.ADD') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
```

**Seletor de `assignee_id`** (omitido do snippet acima por brevidade, adicionar como select
condicional): restringir as opções conforme o contexto —
- `remindableType === 'PipelineItem'` → `pipelineMembers/getPipelineMembers(pipelineId)` (store já
  criada na task 09 do Kanban; o `pipelineId` precisa ser resolvido a partir do `PipelineItem` —
  passar como prop extra `pipelineId` de quem instancia o modal a partir do Kanban).
- `remindableType === 'Conversation'` → membros da inbox/time da conversa (reaproveitar o mesmo
  padrão de `ConversationAction.vue`/`useAgentsList`).
- Caso contrário (Contact, solto) → todos os agentes da conta (`agents/getAgents`).

Formulário standalone (aberto a partir da tela "Lembretes", sem `remindableType`/`remindableId`
vindo de props) fica restrito a "lembrete solto" nesta primeira versão — um seletor livre de
`remindable` (buscar conversa/contato/oportunidade) é o ponto mais complexo do form e não é
essencial pro MVP; pode ser adicionado depois como melhoria.

---

## 3. Composição nos 3 pontos

### 3.1 Conversa — `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`

Esse arquivo já usa um padrão de **seções arrastáveis/opcionais** (`Draggable` + `AccordionItem`,
controlado por `conversationSidebarItemsOrder`/`conversationSidebarItems`, com blocos
`v-else-if="element.name === 'contact_notes'"` etc. — confirmado por leitura direta, é exatamente
o "sidebar com seções" que outras integrações como Shopify/Linear usam). Seguir o mesmo padrão em
vez de inventar um bloco fixo à parte:

1. Adicionar um branch novo dentro do loop de `Draggable`:
```html
<div v-else-if="element.name === 'reminders'">
  <AccordionItem
    :title="t('REMINDERS.TITLE')"
    :is-open="isContactSidebarItemOpen('is_reminders_open')"
    @toggle="value => toggleSidebarUIState('is_reminders_open', value)"
  >
    <RemindersSection remindable-type="Conversation" :remindable-id="conversationId" />
  </AccordionItem>
</div>
```
2. Importar `RemindersSection` no topo do arquivo.
3. Incluir `'reminders'` na lista default de `conversationSidebarItemsOrder` — localizar onde esse
   default é definido (provavelmente dentro do composable `useUISettings`, procurar a constante que
   lista os nomes válidos tipo `'contact_notes'`, `'previous_conversation'`, etc., e adicionar
   `'reminders'` nela).

### 3.2 Contato — `app/javascript/dashboard/routes/dashboard/contacts/pages/ContactManageView.vue`

Confirmado por leitura direta: já existe um array `CONTACT_TABS_OPTIONS` controlando um `TabBar`
(`attributes`/`history`/`notes`/`merge`). Adicionar mais uma entrada:

```javascript
const CONTACT_TABS_OPTIONS = [
  { key: 'ATTRIBUTES', value: 'attributes' },
  { key: 'HISTORY', value: 'history' },
  { key: 'NOTES', value: 'notes' },
  { key: 'REMINDERS', value: 'reminders' },
  { key: 'MERGE', value: 'merge' },
];
```

E no template, ao lado de `<ContactNotes v-if="activeTab === 'notes'" />`:
```html
<RemindersSection
  v-if="activeTab === 'reminders'"
  remindable-type="Contact"
  :remindable-id="selectedContact.id"
/>
```

Chave i18n nova: `CONTACTS_LAYOUT.SIDEBAR.TABS.REMINDERS` (arquivo onde as demais chaves de
`CONTACT_TABS_OPTIONS` já vivem).

### 3.3 Kanban — `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue`

Adicionar a seção no painel de detalhe do card, junto de notes/assignee/labels (já adicionados
pelas tasks 09/10 do Kanban):

```html
<div>
  <RemindersSection remindable-type="PipelineItem" :remindable-id="item.id" />
</div>
```

---

## 4. i18n

`en/reminder.json` — completar com:
```json
"REMINDERS": {
  "EMPTY_STATE": "No reminders yet.",
  "FORM": {
    "TITLE_LABEL": "Title",
    "DESCRIPTION_LABEL": "Description (optional)",
    "DUE_AT_LABEL": "Due date and time",
    "ASSIGNEE_LABEL": "Assign to",
    "CANCEL": "Cancel"
  },
  "API": {
    "CREATE_SUCCESS": "Reminder created successfully."
  }
}
```
`pt_BR/reminder.json` — traduzir integralmente.

`CONTACTS_LAYOUT.SIDEBAR.TABS.REMINDERS`: `"Reminders"` / `"Lembretes"`.

---

## Verificação

1. Abrir uma conversa — nova seção "Lembretes" aparece na lista de accordions da sidebar de
   contato/conversa, reordenável junto com as demais (mesmo comportamento de Notes/Shopify/Linear).
2. Criar um lembrete ali — aparece na seção e também na tela "Lembretes" standalone (task 20),
   já vinculado àquela conversa.
3. Abrir um contato — nova aba "Lembretes" ao lado de Notas/Histórico/Mesclar.
4. Abrir uma oportunidade no Kanban — seção "Lembretes" aparece no painel de detalhe do card.
5. Criar lembrete a partir de cada um dos 3 pontos, marcar como concluído inline (checkbox) em
   cada um — reflete em tempo real na store (mesmo lembrete usado nos 3 lugares se navegar entre eles).
