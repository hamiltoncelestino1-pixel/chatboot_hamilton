# Task: Board Kanban — Tela de Trabalho (criar contato junto, link pro contato, limpeza)

## Objetivo

Depois que Configurações > Pipelines (task `12-feat-pipeline-settings-page.md`) assume o CRUD de
pipeline/etapa, o board Kanban (`/accounts/:id/kanban`) vira uma tela **só de trabalho**: escolher
pipeline, arrastar cards entre etapas, criar/editar oportunidades. Esta task cobre o que falta
nessa tela:

1. **Criar contato junto da oportunidade** — hoje `AddItemModal.vue` só busca contato existente via
   `ContactAPI.search`, sem opção de criar um novo.
2. **Link da oportunidade para o contato** — hoje o nome/avatar do contato no card e no detalhe é só
   texto estático, sem navegação.
3. **Limpeza do board** — remover `AddPipelineModal.vue` e qualquer botão de criar/editar/excluir
   pipeline/etapa (migrados para Configurações na task 12); remover textos hardcoded em pt-BR
   remanescentes.

**Pré-requisito:** task 12 implementada (senão o botão "Criar Pipeline" ainda é necessário no
board como fallback).

---

## 1. Criar contato junto da oportunidade

O projeto já tem exatamente esse padrão pronto e testado em produção: **"Nova Conversa"**
(`app/javascript/dashboard/components-next/NewConversation/ComposeConversation.vue`) usa
`ContactSelector.vue` (`components-next/NewConversation/components/ContactSelector.vue`) — um
`TagInput` com `allow-create` que dispara `@add` tanto para selecionar um contato existente quanto
para sinalizar criação de um novo — combinado com os helpers de
`components-next/NewConversation/helpers/composeConversationHelper.js`:

- `createContactSearcher()` — factory que devolve uma função de busca com abort de request
  concorrente (usa `ContactAPI.search`).
- `createNewContact(input)` — recebe uma string (email ou telefone, detecta pelo prefixo `+`) e
  cria o contato via `ContactAPI.create`.

O handler real em `ComposeConversation.vue` (linha ~107) é:

```javascript
const handleSelectedContact = async ({ value, action, ...rest }) => {
  let contact;
  if (action === 'create') {
    isCreatingContact.value = true;
    try {
      contact = await createNewContact(value);
      isCreatingContact.value = false;
    } catch (error) {
      isCreatingContact.value = false;
      return;
    }
  } else {
    contact = rest;
  }
  selectedContact.value = contact;
  contacts.value = [];
};
```

### Reescrever `app/javascript/dashboard/routes/dashboard/kanban/components/AddItemModal.vue`

Substituir o bloco de busca manual (`<input>` + `ContactAPI.search` direto) por `ContactSelector`
real, replicando o mesmo padrão:

```vue
<script setup>
import { ref, reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ContactSelector from 'dashboard/components-next/NewConversation/components/ContactSelector.vue';
import {
  createContactSearcher,
  createNewContact,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

const props = defineProps({
  stageId: { type: Number, default: null },
});
const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('kanban/getUIFlags');
const activePipeline = useMapGetter('kanban/getActivePipeline');
const getStagesForPipeline = useMapGetter('kanban/getStagesForPipeline');

const stages = computed(() =>
  activePipeline.value ? getStagesForPipeline.value(activePipeline.value.id) : []
);

const form = reactive({
  title: '',
  value: '',
  pipeline_stage_id: props.stageId || stages.value[0]?.id || null,
});

const searchContactsFn = createContactSearcher();
const contacts = ref([]);
const selectedContact = ref(null);
const isSearching = ref(false);
const isCreatingContact = ref(false);
const showContactsDropdown = ref(false);

const handleSearchContacts = async query => {
  showContactsDropdown.value = true;
  isSearching.value = true;
  contacts.value = await searchContactsFn(query);
  isSearching.value = false;
};

const handleSetSelectedContact = async ({ value, action, ...rest }) => {
  if (action === 'create') {
    isCreatingContact.value = true;
    try {
      selectedContact.value = await createNewContact(value);
    } catch {
      useAlert(t('KANBAN.ITEM.CONTACT_SELECTOR.CREATE_ERROR'));
      return;
    } finally {
      isCreatingContact.value = false;
    }
  } else {
    selectedContact.value = rest;
  }
  contacts.value = [];
  showContactsDropdown.value = false;
};

const clearSelectedContact = () => {
  selectedContact.value = null;
};

const handleSubmit = async () => {
  if (!selectedContact.value) return;
  try {
    const item = await store.dispatch('kanban/createItem', {
      contact_id: selectedContact.value.id,
      pipeline_stage_id: form.pipeline_stage_id || stages.value[0]?.id,
      title: form.title || null,
      value: form.value || null,
    });
    useAlert(t('KANBAN.ITEM.API.CREATE_SUCCESS'));
    emit('created', item);
    emit('close');
  } catch {
    useAlert(t('KANBAN.ITEM.API.ERROR'));
  }
};
</script>

<template>
  <Teleport to="body">
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="fixed inset-0 bg-black/30" @click="emit('close')" />
      <div class="relative w-full max-w-md bg-white dark:bg-slate-800 rounded-xl shadow-xl z-10">
        <div class="flex items-center justify-between px-6 py-4 border-b border-slate-100 dark:border-slate-700">
          <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100">
            {{ t('KANBAN.ITEM.ADD') }}
          </h3>
          <button class="text-slate-400 hover:text-slate-600" @click="emit('close')">
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <ContactSelector
          :contacts="contacts"
          :selected-contact="selectedContact"
          :show-contacts-dropdown="showContactsDropdown"
          :is-loading="isSearching"
          :is-creating-contact="isCreatingContact"
          :contactable-inboxes-list="[]"
          :show-inboxes-dropdown="false"
          @search-contacts="handleSearchContacts"
          @set-selected-contact="handleSetSelectedContact"
          @clear-selected-contact="clearSelectedContact"
        />

        <div class="px-6 py-4 space-y-4">
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1">
              {{ t('KANBAN.STAGE.NAME_LABEL') }}
            </label>
            <select v-model="form.pipeline_stage_id" class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700">
              <option v-for="stage in stages" :key="stage.id" :value="stage.id">{{ stage.name }}</option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1">
              {{ t('KANBAN.ITEM.TITLE_LABEL') }}
            </label>
            <input v-model="form.title" type="text" class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700" :placeholder="t('KANBAN.ITEM.TITLE_PLACEHOLDER')" />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1">
              {{ t('KANBAN.ITEM.VALUE_LABEL') }}
            </label>
            <input v-model="form.value" type="number" step="0.01" min="0" class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700" :placeholder="t('KANBAN.ITEM.VALUE_PLACEHOLDER')" />
          </div>
        </div>

        <div class="flex items-center justify-end gap-2 px-6 py-4 border-t border-slate-100 dark:border-slate-700">
          <button class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400" @click="emit('close')">
            {{ t('KANBAN.ITEM.CANCEL') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg disabled:opacity-50 flex items-center gap-2"
            :disabled="!selectedContact || uiFlags.isCreating"
            @click="handleSubmit"
          >
            <span v-if="uiFlags.isCreating" class="i-lucide-loader size-4 animate-spin" />
            {{ t('KANBAN.ITEM.ADD') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
```

Substitui integralmente o `<input>` de busca manual e a lista de resultados hardcoded do arquivo
atual pelo `ContactSelector` real — que já sabe renderizar resultados, estado de loading e estado
de "criando contato...".

---

## 2. Link da oportunidade para o contato

Rota real confirmada em `app/javascript/dashboard/routes/dashboard/contacts/routes.js:44-53`:
`name: 'contacts_edit'`, `path: 'accounts/:accountId/contacts/:contactId'`.

### `KanbanCard.vue`

Envolver o bloco de avatar/nome do contato num `router-link`, usando `useRoute`/`useAccount` para
pegar `accountId` (ou `useMapGetter('getCurrentAccountId')`, padrão já usado em outros componentes
do dashboard):

```vue
<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const accountId = computed(() => route.params.accountId);
</script>
```

```html
<router-link
  :to="{ name: 'contacts_edit', params: { accountId: accountId, contactId: item.contact.id } }"
  class="flex items-center gap-2 mb-1.5 hover:underline"
  @click.stop
>
  <!-- avatar + nome, mesmo conteúdo já existente -->
</router-link>
```

`@click.stop` é necessário para não disparar o `@click="emit('click', item)"` do card inteiro
(abrir o slide-over) ao clicar especificamente no nome do contato.

### `KanbanCardDetail.vue`

Mesmo tratamento no bloco de contato do slide-over (topo do painel), envolvendo nome +
email/telefone num `router-link` equivalente, com um ícone `i-lucide-external-link` ao lado.

---

## 3. Limpeza do board (dependente da task 12 já ter sido aplicada)

- Excluir `app/javascript/dashboard/routes/dashboard/kanban/components/AddPipelineModal.vue`.
- `KanbanIndex.vue`: remover o botão/estado que abria esse modal; se não houver nenhum pipeline
  (`hasPipelines === false`), o `KanbanEmptyState.vue` deve direcionar para
  `{ name: 'pipelines_list' }` (Configurações > Pipelines) em vez de abrir um modal local.
- Substituir os textos hardcoded em pt-BR restantes por chaves i18n:
  - `KanbanCardDetail.vue`: `"Cancelar"` → `t('KANBAN.ITEM.CANCEL')`, `"Salvar"` →
    `t('KANBAN.ITEM.SAVE')`.
  - `store/modules/kanban/actions.js`: as chamadas `useAlert('Erro ao mover card...')`, `'Erro ao
    reordenar etapas...'`, `'Erro ao reordenar cards...'` devem usar `i18n.global.t(...)` (ver como
    outras actions de store fazem isso no projeto — geralmente importando `i18n` diretamente no
    arquivo de actions) com as chaves `KANBAN.ITEM.MOVE_ERROR`, `KANBAN.STAGE.REORDER_ERROR`,
    `KANBAN.ITEM.REORDER_ERROR` (já previstas no i18n original da task 07).

---

## i18n

`en/kanban.json` (`KANBAN.ITEM`):
```json
"CANCEL": "Cancel",
"SAVE": "Save",
"CONTACT_SELECTOR": {
  "CREATE_ERROR": "Failed to create contact. Please try again."
}
```

`pt_BR/kanban.json`:
```json
"CANCEL": "Cancelar",
"SAVE": "Salvar",
"CONTACT_SELECTOR": {
  "CREATE_ERROR": "Falha ao criar contato. Tente novamente."
}
```

`COMPOSE_NEW_CONVERSATION.FORM.CONTACT_SELECTOR.*` (já existentes) são reaproveitadas diretamente
pelo `ContactSelector.vue` — não precisam ser duplicadas, pois o componente usa esse namespace fixo
internamente (`i18nPrefix = 'COMPOSE_NEW_CONVERSATION.FORM.CONTACT_SELECTOR'`).

---

## Verificação

1. Abrir "Adicionar oportunidade" no board — buscar um telefone/email que não existe, confirmar
   contato → contato é criado e a oportunidade é salva com esse `contact_id`.
2. Buscar um contato existente → seleciona normalmente (fluxo antigo continua funcionando).
3. Clicar no nome do contato num card ou no slide-over → navega para `/accounts/:id/contacts/:id`.
4. Confirmar que arrastar o card não é acionado ao clicar no link do contato (click.stop correto).
5. Sem nenhum pipeline cadastrado, o board mostra o empty state apontando para Configurações >
   Pipelines (não há mais modal local de criar pipeline no board).
6. Nenhum texto em pt-BR hardcoded restante no board (grep por strings soltas nos componentes).
