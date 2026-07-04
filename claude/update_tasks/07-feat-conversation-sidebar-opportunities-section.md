# Task: Seção "Oportunidades" na sidebar da conversa

## Objetivo

Adicionar um novo menu colapsável "Oportunidades" na sidebar direita da conversa (junto de "Ações
da conversa", "Macros", "Informação da conversa", etc.), mostrando as oportunidades já vinculadas à
conversa (título, pipeline, link pro card) e permitindo criar uma nova oportunidade direto dali —
com o contato e a conversa já pré-selecionados.

**Pré-requisito**: task `06-feat-pipeline-items-lookup-by-contact-conversation-and-visibility-scope.md`
implementada (getter `kanban/getItemsForConversation`, action `kanban/fetchItemsForConversation`).
**Depende também** da task `09-feat-add-item-modal-contact-conversation-prefill.md` para a criação
inline funcionar (pode ser implementada em conjunto).

## Diagnóstico (código atual verificado)

`app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` renderiza a sidebar como
uma lista `Draggable` de seções, cada uma condicionada por `element.name === 'xxx'`, dentro de um
`AccordionItem`. A ordem/config das seções vem de
`app/javascript/dashboard/composables/useUISettings.js:4-14`:

```javascript
export const DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER = Object.freeze([
  { name: 'conversation_actions' },
  { name: 'macros' },
  { name: 'conversation_info' },
  { name: 'contact_attributes' },
  { name: 'contact_notes' },
  { name: 'previous_conversation' },
  { name: 'conversation_participants' },
  { name: 'linear_issues' },
  { name: 'shopify_orders' },
]);
```

Padrão exato de uma seção existente (`previous_conversation`, `ContactPanel.vue:222-234`):

```vue
<div v-else-if="element.name === 'previous_conversation'">
  <AccordionItem
    v-if="contact.id"
    :title="$t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')"
    :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
    compact
    @toggle="value => toggleSidebarUIState('is_previous_conv_open', value)"
  >
    <ContactConversations ... />
  </AccordionItem>
</div>
```

O toggle de aberto/fechado usa `isContactSidebarItemOpen(key)`/`toggleSidebarUIState(key)`, ambos
já desestruturados de `useUISettings()` no topo do componente.

`app/javascript/dashboard/routes/dashboard/kanban/pages/KanbanIndex.vue` hoje não lê nenhum query
param — precisa ganhar suporte a deep link pra "ver no pipeline" funcionar.

---

## 1. `useUISettings.js`

Adicionar `{ name: 'opportunities' }` ao array `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` (linha
4-14) — posição sugerida: logo após `previous_conversation`.

## 2. Novo componente — `app/javascript/dashboard/components-next/Conversation/ConversationOpportunities.vue`

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
  conversationId: { type: Number, required: true },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const isFetching = ref(true);
const showAddItemModal = ref(false);

const itemsGetter = useMapGetter('kanban/getItemsForConversation');
const items = computed(() => itemsGetter.value(props.conversationId));

onMounted(async () => {
  try {
    await store.dispatch('kanban/fetchItemsForConversation', props.conversationId);
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
          {{ t('CONVERSATION_SIDEBAR.OPPORTUNITIES.EMPTY_STATE') }}
        </p>
        <button
          class="px-3 py-1.5 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg"
          @click="showAddItemModal = true"
        >
          {{ t('CONVERSATION_SIDEBAR.OPPORTUNITIES.CREATE') }}
        </button>
      </div>
      <div v-else class="space-y-2">
        <button
          v-for="item in items"
          :key="item.id"
          class="w-full text-left p-2 rounded-lg border border-n-weak hover:bg-n-alpha-1"
          @click="goToOpportunity(item)"
        >
          <p class="text-sm font-medium text-n-slate-12 truncate">{{ item.title || item.contact?.name }}</p>
          <p class="text-xs text-n-slate-11">{{ item.pipeline_name }} · {{ item.pipeline_stage?.name }}</p>
        </button>
        <button
          class="text-sm text-woot-500 hover:text-woot-600 font-medium"
          @click="showAddItemModal = true"
        >
          + {{ t('CONVERSATION_SIDEBAR.OPPORTUNITIES.CREATE') }}
        </button>
      </div>
    </template>

    <AddItemModal
      v-if="showAddItemModal"
      :contact-id="contactId"
      :conversation-id="conversationId"
      @close="showAddItemModal = false"
      @created="showAddItemModal = false"
    />
  </div>
</template>
```

(Import de `AddItemModal.vue` fora da pasta `kanban/` — confirmar durante a implementação se vale a
pena mover `AddItemModal.vue` para um local mais compartilhado, ex.
`components-next/Pipeline/AddItemModal.vue`, já que passa a ser usado por 3 contextos diferentes:
board, conversa e contato. Se mover, atualizar os imports em `KanbanIndex.vue` também.)

## 3. `ContactPanel.vue`

Adicionar o bloco novo, mesmo padrão dos existentes — inserir próximo a `previous_conversation`
(linha ~222):

```vue
<div v-else-if="element.name === 'opportunities'">
  <AccordionItem
    v-if="contact.id"
    :title="$t('CONVERSATION_SIDEBAR.ACCORDION.OPPORTUNITIES')"
    :is-open="isContactSidebarItemOpen('is_opportunities_open')"
    compact
    @toggle="value => toggleSidebarUIState('is_opportunities_open', value)"
  >
    <ConversationOpportunities
      :contact-id="contact.id"
      :conversation-id="conversationId"
    />
  </AccordionItem>
</div>
```

Importar `ConversationOpportunities` no topo do arquivo. Confirmar o nome exato da variável/prop
`conversationId` já disponível no escopo de `ContactPanel.vue` (usada por outras seções como
`macros`, linha ~250 — `<MacrosList :conversation-id="conversationId" />`).

## 4. Deep link "Ver no pipeline" — `KanbanIndex.vue`

```javascript
import { useRoute } from 'vue-router';

const route = useRoute();

onMounted(async () => {
  store.dispatch('attributes/get');
  await store.dispatch('kanban/fetchPipelines');
  const targetPipelineId = Number(route.query.pipelineId) || pipelines.value[0]?.id;
  if (targetPipelineId) {
    store.commit('kanban/SET_ACTIVE_PIPELINE', targetPipelineId);
    await store.dispatch('kanban/fetchItems', targetPipelineId);
  }
  if (route.query.itemId) {
    selectedCardId.value = Number(route.query.itemId);
  }
});
```

(substituir o `onMounted` atual, linhas 29-38 — preservar a lógica existente de "se não tem
`activePipeline`, usa o primeiro pipeline"; a mudança só adiciona a leitura de `route.query` como
fonte alternativa/prioritária de qual pipeline/card abrir.)

## 5. i18n

`app/javascript/dashboard/i18n/locale/en/conversation.json` (ou onde vive `CONVERSATION_SIDEBAR.ACCORDION.*`):
```json
"CONVERSATION_SIDEBAR": {
  "ACCORDION": {
    "OPPORTUNITIES": "Opportunities"
  },
  "OPPORTUNITIES": {
    "EMPTY_STATE": "No opportunities linked to this conversation",
    "CREATE": "Create opportunity"
  }
}
```

`pt_BR` equivalente:
```json
"CONVERSATION_SIDEBAR": {
  "ACCORDION": {
    "OPPORTUNITIES": "Oportunidades"
  },
  "OPPORTUNITIES": {
    "EMPTY_STATE": "Nenhuma oportunidade vinculada a esta conversa",
    "CREATE": "Criar oportunidade"
  }
}
```

---

## Verificação

1. Abrir uma conversa cujo contato já tenha uma oportunidade com essa conversa vinculada
   (`conversation_id`) — a seção "Oportunidades" deve mostrar o card com título/pipeline/etapa.
2. Clicar no card — deve navegar para `/app/accounts/:id/kanban?pipelineId=X&itemId=Y` e abrir
   automaticamente o painel de detalhe daquela oportunidade.
3. Abrir uma conversa sem nenhuma oportunidade vinculada — deve mostrar o empty state com botão
   "Criar oportunidade".
4. Clicar em "Criar oportunidade" — abre o modal com contato e conversa já pré-selecionados
   (validar via task 09), escolher um pipeline e criar — a nova oportunidade deve aparecer na lista
   imediatamente.
5. Testar como agente sem acesso a nenhum pipeline — a seção deve continuar funcional (empty state),
   sem erro.
6. Arrastar a seção "Oportunidades" para outra posição na sidebar (drag-and-drop já suportado pelo
   `Draggable` existente) — a posição deve persistir após reload (mesmo mecanismo de
   `conversation_sidebar_items_order` já usado pelas outras seções).
