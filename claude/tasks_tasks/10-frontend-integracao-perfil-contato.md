# Task 10 — Frontend: aba "Tarefas" no perfil do contato

Parte do Grupo B ([visão geral](00-visao-geral.md)). Depende da [07](07-frontend-componente-compartilhado.md).

## Objetivo

Adicionar "Tarefas" como mais uma aba no perfil do contato
(`routes/dashboard/contacts/pages/ContactManageView.vue`). **Atenção**: este painel usa abas
fixas (`CONTACT_TABS_OPTIONS` + `activeTab`), não o sistema de ordem arrastável/`AccordionItem`
da sidebar de conversa (task 09) — não copiar o padrão da task 09 aqui, são dois mecanismos de
UI diferentes no mesmo projeto.

## Implementação

`app/javascript/dashboard/routes/dashboard/contacts/pages/ContactManageView.vue`:

1. Import: `import ContactTasks from 'dashboard/components-next/Contacts/ContactsSidebar/ContactTasks.vue';`
2. `CONTACT_TABS_OPTIONS` (linha ~40-46) — adicionar uma entrada, ex. depois de `opportunities`
   (ler o array completo antes, para manter a ordem visual coerente com o que já existe):
   ```js
   { key: 'TASKS', value: 'tasks' },
   ```
3. Novo bloco no template, ao lado de `ContactOpportunities` (linha ~183-186):
   ```vue
   <ContactTasks
     v-if="activeTab === 'tasks'"
     :contact-id="Number(route.params.contactId)"
   />
   ```
4. **Não precisa** de um `fetchContactTasks` chamado em `onMounted` como
   `fetchContactOpportunities` (linha 91-95) — diferente de `kanban/fetchItemsForContact`, que é
   chamado eager porque `ContactOpportunities` é montado sem `v-if` na versão antiga
   (checar se isso mudou); como `ContactTasks`/`TaskList` (task 07) já faz seu próprio fetch em
   `onMounted` quando a aba fica ativa (`v-if` monta o componente só quando `activeTab ===
   'tasks'`), não duplicar a chamada aqui.

## `components-next/Contacts/ContactsSidebar/ContactTasks.vue`

Wrapper fino sobre `TaskList` (mirror de `ContactOpportunities.vue`):

```vue
<script setup>
import TaskList from 'dashboard/components-next/Tasks/TaskList.vue';

defineProps({
  contactId: { type: Number, required: true },
});
</script>

<template>
  <TaskList :contact-id="contactId" />
</template>
```

## i18n

`CONTACTS_LAYOUT.SIDEBAR.TABS.TASKS` (label da aba, mesmo arquivo/domínio de
`CONTACTS_LAYOUT.SIDEBAR.TABS.ATTRIBUTES`/`HISTORY` já existentes) — não é domínio Kanban,
segue a regra geral (só `en`), a menos que o arquivo específico de `CONTACTS_LAYOUT` já seja
outro dos domínios com exceção (conferir antes, mesma checagem da task 09).

## Testes

Não aplicável além do que já está coberto pelas tasks 06/07.

## Critério de pronto

- Abrir o perfil de um contato (`pnpm dev`), a aba "Tarefas" aparece na lista de abas, lista e
  cria tarefas vinculadas àquele contato (sem conversa/card).
- Uma tarefa criada aqui (só com `contact_id`) não quebra a renderização nos outros 2 pontos de
  entrada quando não há `conversation_id`/`pipeline_item_id` (risco #4 da visão geral).
