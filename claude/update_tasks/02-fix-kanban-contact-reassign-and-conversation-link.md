# Task: Contato vinculado — trocar contato, link para página do contato, vincular conversa

## Objetivo

No painel "Editar card" do Kanban:

1. Permitir trocar o contato vinculado à oportunidade.
2. Adicionar um link para abrir a página do contato na aba Contatos.
3. Permitir vincular (opcionalmente) uma conversa do contato à oportunidade, escolhendo entre as
   conversas existentes desse contato via dropdown.
4. Quando houver uma conversa vinculada, exibir um link clicável que abre a conversa (em nova aba,
   igual já acontece no histórico de conversas da aba Contatos).

## Diagnóstico (código atual verificado)

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue:151-174` mostra o
contato só como leitura (avatar, nome, email, telefone) — sem ação nenhuma.

`app/models/pipeline_item.rb:41-42` já tem:

```ruby
belongs_to :contact
belongs_to :conversation, optional: true
```

`app/controllers/api/v1/accounts/pipeline_items_controller.rb` (`item_params`) já permite
`:contact_id` e `:conversation_id` — **o backend já aceita ambos, falta só a UI**.

`KanbanCardDetail.vue:313-320` já mostra `item.conversation_id`, mas só como texto `#123`, sem link
nem forma de trocar/remover.

Padrão de referência para listar/abrir conversas de um contato:
`app/javascript/dashboard/routes/dashboard/conversation/ContactConversations.vue`:
- Getter: `contactConversations/getContactConversation(contactId)` (retorna array, ou `[]`).
- Action: `contactConversations/get(contactId)`.
- Construção da URL: `conversationUrl({...})` + `frontendURL(...)`
  (`app/javascript/dashboard/helper/URLHelper.js`).
- Abertura: `router.push({ path })` no clique normal; `window.open(`${window.chatwootConfig.hostURL}${path}`, '_blank', 'noopener,noreferrer')` quando `metaKey`/`ctrlKey`.

Padrão de referência para trocar contato: `app/javascript/dashboard/components-next/NewConversation/components/ContactSelector.vue`
usa `TagInput mode="single"` com `menu-items` vindo de uma busca de contatos — não precisa ser
reaproveitado como componente (tem lógica de criação de conversa acoplada), só como referência do
fluxo de busca (`contacts/search`/`contacts/filter`, já usados em outros pontos do dashboard).

---

## 1. Backend

### 1.1 `app/models/pipeline_item.rb`

Adicionar validação para impedir vincular uma conversa que não seja do mesmo contato:

```ruby
validate :conversation_must_belong_to_contact, if: -> { conversation_id.present? }

private

def conversation_must_belong_to_contact
  return if conversation&.contact_id == contact_id

  errors.add(:conversation_id, I18n.t('errors.pipeline_item.conversation_contact_mismatch'))
end
```

(confirmar chave i18n existente em `config/locales/en.yml` sob `errors.pipeline_item.*` — criar se
não existir, seguindo o padrão das mensagens de erro já usadas por `PipelineItem`.)

---

## 2. Frontend — Kanban

### 2.1 `KanbanCardDetail.vue` — trocar contato

Adicionar estado local:

```javascript
const isChangingContact = ref(false);
const contactSearchResults = useMapGetter('contacts/getContacts'); // confirmar getter exato usado por buscas de contato existentes no projeto
const isSearchingContacts = ref(false);

const searchContacts = async query => {
  if (!query) return;
  isSearchingContacts.value = true;
  try {
    await store.dispatch('contacts/search', { search: query });
  } finally {
    isSearchingContacts.value = false;
  }
};

const contactMenuItems = computed(() =>
  contactSearchResults.value.map(({ id, name, email, thumbnail }) => ({
    label: email ? `${name} (${email})` : name,
    value: id,
    action: 'select',
    thumbnail: { name, src: thumbnail },
  }))
);

const onSelectContact = async ({ value }) => {
  await store.dispatch('kanban/updateItem', { id: props.item.id, contact_id: value });
  isChangingContact.value = false;
};
```

No template, no bloco do contato (linhas 151-174), adicionar ao lado do nome:

```vue
<div class="flex items-center gap-2 ml-auto">
  <router-link
    :to="{ name: 'contacts_edit', params: { contactId: item.contact.id } }"
    target="_blank"
    class="text-slate-400 hover:text-woot-500"
    :title="t('KANBAN.ITEM.CONTACT.VIEW_PROFILE')"
  >
    <span class="i-lucide-external-link size-4" />
  </router-link>
  <button
    class="text-slate-400 hover:text-woot-500"
    :title="t('KANBAN.ITEM.CONTACT.CHANGE')"
    @click="isChangingContact = true"
  >
    <span class="i-lucide-repeat size-4" />
  </button>
</div>
```

Abaixo do bloco de exibição do contato, adicionar (visível apenas quando `isChangingContact`):

```vue
<TagInput
  v-if="isChangingContact"
  mode="single"
  :placeholder="t('KANBAN.ITEM.CONTACT.SEARCH_PLACEHOLDER')"
  :menu-items="contactMenuItems"
  show-dropdown
  :is-loading="isSearchingContacts"
  :auto-open-dropdown="false"
  @input="searchContacts"
  @add="onSelectContact"
  @on-click-outside="isChangingContact = false"
/>
```

Importar `TagInput` de `dashboard/components-next/taginput/TagInput.vue`.

### 2.2 `KanbanCardDetail.vue` — vincular/trocar conversa

Adicionar:

```javascript
const contactConversationsGetter = useMapGetter('contactConversations/getContactConversation');
const contactConversations = computed(() =>
  props.item.contact ? contactConversationsGetter.value(props.item.contact.id) : []
);

watch(
  () => props.item?.contact?.id,
  contactId => {
    if (contactId) store.dispatch('contactConversations/get', contactId);
  },
  { immediate: true }
);

const conversationMenuItems = computed(() =>
  contactConversations.value.map(c => ({
    label: `#${c.id} · ${c.inbox_id ? getInboxName(c.inbox_id) : ''}`, // confirmar helper/getter de nome de inbox já usado no projeto
    value: c.id,
    action: 'select',
  }))
);

const onSelectConversation = async ({ value }) => {
  await store.dispatch('kanban/updateItem', { id: props.item.id, conversation_id: value });
};

const clearConversation = async () => {
  await store.dispatch('kanban/updateItem', { id: props.item.id, conversation_id: null });
};

const linkedConversationUrl = computed(() => {
  if (!props.item.conversation_id) return null;
  return frontendURL(
    conversationUrl({ accountId: route.params.accountId, id: props.item.conversation_id })
  );
});

const openLinkedConversation = e => {
  if (e.metaKey || e.ctrlKey) {
    e.preventDefault();
    window.open(
      `${window.chatwootConfig.hostURL}${linkedConversationUrl.value}`,
      '_blank',
      'noopener,noreferrer'
    );
    return;
  }
  router.push({ path: linkedConversationUrl.value });
};
```

Importar `frontendURL`, `conversationUrl` de `dashboard/helper/URLHelper`, e `useRoute`/`useRouter`
de `vue-router` (confirmar se já importados no arquivo).

Substituir o bloco estático de linhas 313-320 por:

```vue
<div class="p-3 bg-woot-50 dark:bg-woot-900/20 rounded-lg">
  <p class="text-xs font-medium text-woot-700 dark:text-woot-300 mb-1">
    {{ t('KANBAN.ITEM.LINKED_CONVERSATION') }}
  </p>
  <div v-if="item.conversation_id" class="flex items-center justify-between">
    <a
      href="#"
      class="text-sm text-woot-600 dark:text-woot-400 hover:underline"
      @click.prevent="openLinkedConversation"
    >
      #{{ item.conversation_id }}
    </a>
    <button
      class="text-slate-400 hover:text-red-500"
      :title="t('KANBAN.ITEM.CONVERSATION.CLEAR')"
      @click="clearConversation"
    >
      <span class="i-lucide-x size-4" />
    </button>
  </div>
  <TagInput
    v-else
    mode="single"
    :placeholder="t('KANBAN.ITEM.CONVERSATION.SEARCH_PLACEHOLDER')"
    :menu-items="conversationMenuItems"
    show-dropdown
    :auto-open-dropdown="false"
    @add="onSelectConversation"
  />
</div>
```

Manter `v-if="item.contact"` no bloco pai (a seção de conversa só faz sentido com contato definido,
o que já é sempre o caso pois `contact_id` é obrigatório).

### 2.3 i18n

`app/javascript/dashboard/i18n/locale/en/kanban.json` (confirmar nome exato do arquivo — mirror da
estrutura já usada por `KANBAN.ITEM.*`):

```json
"CONTACT": {
  "VIEW_PROFILE": "View contact profile",
  "CHANGE": "Change contact",
  "SEARCH_PLACEHOLDER": "Search contacts..."
},
"CONVERSATION": {
  "SEARCH_PLACEHOLDER": "Link a conversation...",
  "CLEAR": "Unlink conversation"
}
```

`pt_BR/kanban.json`:

```json
"CONTACT": {
  "VIEW_PROFILE": "Ver perfil do contato",
  "CHANGE": "Trocar contato",
  "SEARCH_PLACEHOLDER": "Buscar contatos..."
},
"CONVERSATION": {
  "SEARCH_PLACEHOLDER": "Vincular uma conversa...",
  "CLEAR": "Desvincular conversa"
}
```

---

## Verificação

1. Abrir um card, clicar no ícone de trocar contato, buscar e selecionar outro contato — o card
   deve atualizar com os novos dados de contato, e a listagem de conversas do dropdown deve mudar
   para as conversas do novo contato.
2. Clicar no ícone de "ver perfil" — deve abrir a página do contato em `/app/accounts/:id/contacts/:contactId`.
3. Com o dropdown de conversas, selecionar uma conversa do contato atual — deve salvar
   `conversation_id` e mostrar o link `#123`.
4. Clicar no link `#123` — deve navegar para a conversa; com Ctrl/Cmd + clique, deve abrir em nova
   aba.
5. Clicar no "x" ao lado do link — deve desvincular a conversa e voltar a mostrar o dropdown de
   busca.
6. Tentar (via request direto, não pela UI) vincular uma conversa que não pertence ao contato atual
   — deve retornar erro de validação (`conversation_must_belong_to_contact`).
