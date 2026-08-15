# Task 09 — Frontend: seção "Tarefas" na sidebar da conversa

Parte do Grupo B ([visão geral](00-visao-geral.md)). Depende da [07](07-frontend-componente-compartilhado.md).

## Objetivo

Adicionar "Tarefas" como mais um item arrastável/colapsável na sidebar direita da conversa,
copiando 1:1 o padrão de `opportunities` (`ConversationOpportunities.vue` +
`ContactPanel.vue:241-256`).

## 1. `composables/useUISettings.js`

`DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` (linha 4-15) — adicionar `{ name: 'tasks' }` à
lista, logo após `{ name: 'opportunities' }`:

```js
export const DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER = Object.freeze([
  { name: 'conversation_actions' },
  { name: 'macros' },
  { name: 'conversation_info' },
  { name: 'contact_attributes' },
  { name: 'contact_notes' },
  { name: 'previous_conversation' },
  { name: 'opportunities' },
  { name: 'tasks' },
  { name: 'conversation_participants' },
  { name: 'linear_issues' },
  { name: 'shopify_orders' },
]);
```

Usuários que já têm uma ordem customizada salva (`uiSettings.conversation_sidebar_items_order`)
não ganham o item novo automaticamente — checar como `useConversationSidebarItemsOrder`
(mesmo arquivo, função que lê `uiSettings`) lida com itens ausentes no array salvo do usuário
antes de assumir que isso é ou não um problema; se precisar, mesclar itens novos do default que
não estão no array salvo do usuário (ler a função completa antes de decidir).

## 2. `components-next/Conversation/ConversationTasks.vue`

Wrapper fino sobre `TaskList` (mirror de `ConversationOpportunities.vue`, mas delegando toda a
lógica de fetch/lista para o componente compartilhado da task 07):

```vue
<script setup>
import TaskList from 'dashboard/components-next/Tasks/TaskList.vue';

defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], required: true },
});
</script>

<template>
  <TaskList :contact-id="contactId" :conversation-id="conversationId" />
</template>
```

## 3. `routes/dashboard/conversation/ContactPanel.vue`

Novo bloco `v-else-if`, ao lado do de `opportunities` (linha 241-256):

```vue
<div v-else-if="element.name === 'tasks'">
  <AccordionItem
    v-if="contact.id"
    :title="$t('CONVERSATION_SIDEBAR.ACCORDION.TASKS')"
    :is-open="isContactSidebarItemOpen('is_tasks_open')"
    compact
    @toggle="value => toggleSidebarUIState('is_tasks_open', value)"
  >
    <ConversationTasks
      :contact-id="contact.id"
      :conversation-id="conversationId"
    />
  </AccordionItem>
</div>
```
Import `ConversationTasks` no topo do arquivo.

## i18n

`CONVERSATION_SIDEBAR.ACCORDION.TASKS` — este arquivo de locale (o mesmo domínio usado por
`CONVERSATION_SIDEBAR.ACCORDION.OPPORTUNITIES`) não é um dos 3 domínios da exceção Kanban
(`kanban.json`/`automation.json`/`macros.json`) — checar em qual arquivo `CONVERSATION_SIDEBAR`
mora hoje (provavelmente `conversation.json` ou similar) antes de decidir se segue a regra
geral (só `en`) ou se esse arquivo específico já tem outro precedente de sincronizar pt_BR.

## Testes

Não aplicável além do que já está coberto pelas tasks 06/07.

## Critério de pronto

- Abrir uma conversa (`pnpm dev`), a seção "Tarefas" aparece na sidebar, arrastável junto com
  as outras seções, estado aberto/fechado persiste ao recarregar a página.
- Criar uma tarefa a partir da conversa aparece no card de pipeline vinculado (se houver, task
  08) e no perfil do contato (task 10).
