# Task: Aba "Oportunidades" na página de contato

## Objetivo

Adicionar uma nova aba "Oportunidades" na página de detalhe do contato (junto de "Atributos",
"Histórico", "Notas", "Mesclar"), listando todas as oportunidades vinculadas a esse contato (em
qualquer pipeline) e permitindo criar uma nova oportunidade direto dali — com o contato já
pré-selecionado.

**Pré-requisito**: task `06-feat-pipeline-items-lookup-by-contact-conversation-and-visibility-scope.md`
implementada (getter `kanban/getItemsForContact`, action `kanban/fetchItemsForContact`).
**Depende também** da task `09-feat-add-item-modal-contact-conversation-prefill.md` para a criação
inline funcionar (pode ser implementada em conjunto).

## Diagnóstico (código atual verificado)

`app/javascript/dashboard/routes/dashboard/contacts/pages/ContactManageView.vue:39-44`:

```javascript
const CONTACT_TABS_OPTIONS = [
  { key: 'ATTRIBUTES', value: 'attributes' },
  { key: 'HISTORY', value: 'history' },
  { key: 'NOTES', value: 'notes' },
  { key: 'MERGE', value: 'merge' },
];
```

Renderização condicional (linhas ~152-181):

```vue
<ContactCustomAttributes v-if="activeTab === 'attributes'" :selected-contact="selectedContact" />
<ContactNotes v-if="activeTab === 'notes'" />
<ContactHistory v-if="activeTab === 'history'" />
<ContactMerge v-if="activeTab === 'merge'" ... />
```

Label i18n: `CONTACTS_LAYOUT.SIDEBAR.TABS.{key}`.

Componente de referência estrutural (mesma pegada a seguir):
`app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactHistory.vue` — spinner
enquanto carrega, empty state centralizado, lista com `divide-y divide-n-strong` envolvendo cards.

Padrão de fetch no mount já usado por outras abas em `ContactManageView.vue` (linha ~84):
```javascript
const fetchContactConversations = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('contactConversations/get', contactId);
};
```

---

## 1. `ContactManageView.vue`

```javascript
const CONTACT_TABS_OPTIONS = [
  { key: 'ATTRIBUTES', value: 'attributes' },
  { key: 'HISTORY', value: 'history' },
  { key: 'OPPORTUNITIES', value: 'opportunities' },
  { key: 'NOTES', value: 'notes' },
  { key: 'MERGE', value: 'merge' },
];
```

Adicionar função de fetch (mirror de `fetchContactConversations`):

```javascript
const fetchContactOpportunities = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('kanban/fetchItemsForContact', Number(contactId));
};
```

Chamar `fetchContactOpportunities()` no mesmo ponto onde os outros `fetch*` já são disparados (ex.
dentro do `onMounted`/watcher que também chama `fetchContactNotes`/`fetchContactConversations` —
confirmar o local exato lendo o restante do arquivo antes de aplicar).

No template, adicionar ao lado de `<ContactHistory v-if="activeTab === 'history'" />`:

```vue
<ContactOpportunities
  v-if="activeTab === 'opportunities'"
  :contact-id="Number(route.params.contactId)"
/>
```

Importar `ContactOpportunities` no topo do arquivo.

## 2. Novo componente — `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactOpportunities.vue`

Mesma estrutura de `ContactHistory.vue`:

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AddItemModal from 'dashboard/routes/dashboard/kanban/components/AddItemModal.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const isFetching = ref(true);
const showAddItemModal = ref(false);

const itemsGetter = useMapGetter('kanban/getItemsForContact');
const items = computed(() => itemsGetter.value(props.contactId));

onMounted(async () => {
  try {
    await store.dispatch('kanban/fetchItemsForContact', props.contactId);
  } finally {
    isFetching.value = false;
  }
});

const goToOpportunity = item => {
  router.push({
    name: 'kanban_index',
    query: { pipelineId: item.pipeline_id, itemId: item.id },
  });
};
</script>

<template>
  <div class="px-6 py-4">
    <div v-if="isFetching" class="flex justify-center py-4">
      <Spinner />
    </div>
    <template v-else>
      <div v-if="!items.length" class="text-center py-4">
        <p class="text-sm text-n-slate-11 mb-3">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.EMPTY_STATE') }}
        </p>
        <button
          class="px-3 py-1.5 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg"
          @click="showAddItemModal = true"
        >
          {{ t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.CREATE') }}
        </button>
      </div>
      <div v-else class="divide-y divide-n-strong">
        <button
          v-for="item in items"
          :key="item.id"
          class="w-full text-left py-3 hover:bg-n-alpha-1"
          @click="goToOpportunity(item)"
        >
          <p class="text-sm font-medium text-n-slate-12 truncate">{{ item.title || t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.UNTITLED') }}</p>
          <p class="text-xs text-n-slate-11">{{ item.pipeline_name }} · {{ item.pipeline_stage?.name }}</p>
          <p v-if="item.value" class="text-xs text-emerald-600 dark:text-emerald-400 mt-0.5">
            {{ item.value }}
          </p>
        </button>
        <button
          class="text-sm text-woot-500 hover:text-woot-600 font-medium pt-3"
          @click="showAddItemModal = true"
        >
          + {{ t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.CREATE') }}
        </button>
      </div>
    </template>

    <AddItemModal
      v-if="showAddItemModal"
      :contact-id="contactId"
      @close="showAddItemModal = false"
      @created="showAddItemModal = false"
    />
  </div>
</template>
```

(mesma observação da task 07 sobre considerar mover `AddItemModal.vue` pra um local compartilhado,
já que agora tem 3 consumidores: board, conversa e contato.)

## 3. i18n

`app/javascript/dashboard/i18n/locale/en/contacts.json` (ou onde vive `CONTACTS_LAYOUT.SIDEBAR.TABS`):

```json
"CONTACTS_LAYOUT": {
  "SIDEBAR": {
    "TABS": {
      "OPPORTUNITIES": "Opportunities"
    },
    "OPPORTUNITIES": {
      "EMPTY_STATE": "No opportunities linked to this contact",
      "CREATE": "Create opportunity",
      "UNTITLED": "Untitled opportunity"
    }
  }
}
```

`pt_BR`:
```json
"CONTACTS_LAYOUT": {
  "SIDEBAR": {
    "TABS": {
      "OPPORTUNITIES": "Oportunidades"
    },
    "OPPORTUNITIES": {
      "EMPTY_STATE": "Nenhuma oportunidade vinculada a este contato",
      "CREATE": "Criar oportunidade",
      "UNTITLED": "Oportunidade sem título"
    }
  }
}
```

---

## Verificação

1. Abrir um contato com 2+ oportunidades em pipelines diferentes — a aba "Oportunidades" deve
   listar todas, cada uma mostrando pipeline/etapa corretos.
2. Clicar numa oportunidade da lista — navega para o Kanban, no pipeline certo, com o card aberto.
3. Abrir um contato sem nenhuma oportunidade — mostra empty state com botão de criar.
4. Criar uma oportunidade pelo botão da aba — contato já vem pré-selecionado (validar via task 09);
   a nova oportunidade aparece na lista da aba imediatamente após criar.
5. Testar como agente sem acesso ao pipeline onde a oportunidade do contato está — não deve
   aparecer na lista (a busca por contato também respeita a visibilidade da task 06), a menos que a
   oportunidade esteja atribuída a esse agente ou seja órfã.
