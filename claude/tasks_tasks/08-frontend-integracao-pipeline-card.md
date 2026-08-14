# Task 08 — Frontend: seção "Tarefas" no card de pipeline

Parte do Grupo B ([visão geral](00-visao-geral.md)). Depende da [07](07-frontend-componente-compartilhado.md).

## Objetivo

Adicionar um `AccordionItem` novo "Tarefas" em `KanbanCardDetail.vue`, ao lado do de atributos
customizados (`isAttributesOpen`, linha ~418), embutindo `TaskList` com `pipeline-item-id` +
`contact-id` do card aberto.

## Implementação

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue`:

1. Import: `import TaskList from 'dashboard/components-next/Tasks/TaskList.vue';`
2. Novo `ref` local: `const isTasksOpen = ref(false);` (ao lado de `isAttributesOpen`, linha ~56).
3. Novo `AccordionItem`, logo após o de atributos customizados (depois da linha ~506):

```vue
<AccordionItem
  :title="$t('KANBAN.ITEM.TASKS.TITLE')"
  :is-open="isTasksOpen"
  compact
  @toggle="isTasksOpen = !isTasksOpen"
>
  <TaskList
    :contact-id="item.contact.id"
    :pipeline-item-id="item.id"
  />
</AccordionItem>
```

Confirmar o nome exato da prop/variável que expõe o item atual dentro do componente (pode ser
`item`, `pipelineItem`, ou vir de um `computed` — ler o topo do `<script setup>` de
`KanbanCardDetail.vue` antes de escrever esse trecho, para usar o identificador certo).

## i18n

Chave nova em `KANBAN.ITEM.TASKS.TITLE` — como é domínio Kanban, entra em **`en` e `pt_BR`**
juntos (exceção documentada no `AGENTS.md`/CLAUDE.md para o domínio Kanban/automation/macros).
Ver task 12 para o restante do i18n de Tasks (que não é domínio Kanban e segue a regra geral de
só `en`) — só esta chave específica, por estar dentro do arquivo `kanban.json`, segue a
exceção.

## Testes

Não aplicável nesta task além do que já está coberto pelas tasks 06/07 (sem lógica nova, só
composição de componentes).

## Critério de pronto

- Abrir um card de pipeline (`pnpm dev`), a seção "Tarefas" aparece, expande/colapsa, lista e
  cria tarefas vinculadas àquele card.
- Criar uma tarefa a partir do card e depois abrir o mesmo contato/conversa vinculados (tasks
  09/10, se já implementadas) mostra a mesma tarefa.
