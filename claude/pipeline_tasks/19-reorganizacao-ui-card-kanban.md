# Task 19 — Reorganização da UI do card do Kanban (Editar card)

Task de UI, independente das demais tasks do épico. Escopo restrito ao painel "Editar card"
(`KanbanCardDetail.vue`) — o restante do Kanban (colunas, board, drag-and-drop) não muda.
Motivação: o rodapé de botões está estourando a largura do painel (`max-w-md`, ~448px) e o
menu de "Rodar macro" — hoje um dropdown feito à mão — pode se sobrepor visualmente a
Cancelar/Salvar quando aberto. Além disso, "Conversa vinculada" fica isolada no fim do
formulário, longe do bloco de contato/assignee, e o link `#123` para a conversa é discreto
demais.

Nenhum código Ruby/backend é tocado — não se aplica sincronização com `enterprise/`. Não há
specs existentes para os arquivos tocados; não escrever specs nesta task (regra do projeto).

## 1. i18n — nova chave `KANBAN.ITEM.CONVERSATION.VIEW`

**Arquivos:** `app/javascript/dashboard/i18n/locale/en/kanban.json` e
`app/javascript/dashboard/i18n/locale/pt_BR/kanban.json` (domínio Kanban mantém `pt_BR`
sincronizado manualmente — regra de exceção do `AGENTS.md`/CLAUDE.md, os dois precisam ser
tocados juntos).

Adicionar dentro de `ITEM.CONVERSATION` (ao lado de `SEARCH_PLACEHOLDER`/`CLEAR`, já
existentes em `en/kanban.json:88-91`):
```json
"CONVERSATION": {
  "SEARCH_PLACEHOLDER": "Link a conversation...",
  "CLEAR": "Unlink conversation",
  "VIEW": "View Conversation"
}
```
(pt_BR: `"VIEW": "Ver Conversa"`)

## 2. `KanbanRunMacroMenu.vue` — trocar o dropdown feito à mão pelo `DropdownMenu` do design system

**Arquivo:** `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanRunMacroMenu.vue`

Hoje o painel do menu é um `<div v-if="showMenu">` com Tailwind cru (`border-slate-200
bg-white ... shadow-lg`, `absolute right-0 w-56`). Trocar pelo componente oficial
`app/javascript/dashboard/components-next/dropdown-menu/DropdownMenu.vue`, seguindo o padrão
já usado em `app/javascript/dashboard/components/widgets/conversation/MoreActions.vue`
(trigger + `v-on-clickaway` no wrapper + `<DropdownMenu v-if="..." class="mt-1 ltr:right-0
rtl:left-0 top-full" @action="...">`).

- **Não alterar a API pública do componente** (`pipelineItemIds`, `showLabel`, `buttonClass`)
  — ele é consumido em dois lugares (`KanbanCardDetail.vue` no rodapé, `KanbanColumn.vue` no
  cabeçalho da coluna) e ambos precisam continuar funcionando sem mudança de uso.
- Montar os itens do menu a partir de `pipelineMacros` (computed já existente, linha 20-22):
  ```js
  const macroMenuItems = computed(() =>
    pipelineMacros.value.map(macro => ({
      label: macro.name,
      action: 'run',
      value: macro.id,
      macro,
      icon: executingMacroId.value === macro.id
        ? 'i-lucide-loader animate-spin'
        : 'i-lucide-play',
      disabled: !!executingMacroId.value,
    }))
  );
  ```
  (`Icon.vue` só faz `h('span', { class: props.icon })`, então uma string com duas classes —
  `'i-lucide-loader animate-spin'` — funciona normalmente para manter o spinner por item.)
- Usar `menu-sections`, não `menu-items`, para poder passar o `emptyState` customizado:
  ```vue
  <DropdownMenu
    v-if="showMenu"
    :menu-sections="[{ items: macroMenuItems, emptyState: t('KANBAN.RUN_MACRO.EMPTY_STATE') }]"
    class="mt-1 ltr:right-0 rtl:left-0 top-full"
    @action="({ macro }) => runMacro(macro)"
  />
  ```
- Manter toda a lógica existente de `runMacro`/`executingMacroId`/`useAlert` intacta — só o
  template do painel muda, não o `<script setup>` (fora da nova computed `macroMenuItems`).
- O comentário existente em `runMacro` sobre não refazer fetch após `macros/execute` (linhas
  47-53 atuais) deve ser preservado como está.

## 3. Rodapé de `KanbanCardDetail.vue` — reorganizar para não estourar a largura

**Arquivo:** `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue`,
bloco do rodapé (hoje linhas 563-605).

Grupo esquerdo (Excluir, Exportar, Rodar macro) tem botões com ícone+texto que somados
estouram o painel (`max-w-md`) e podem sobrepor o grupo direito (Cancelar, Salvar). Seguir o
padrão já usado em `KanbanColumn.vue` (`button-class="p-0.5 text-slate-400
hover:text-woot-500"`, só ícone) para os três botões do grupo esquerdo:

- Excluir card → só ícone (`i-lucide-trash-2`) + `v-tooltip` com o texto atual
  (`KANBAN.ITEM.DELETE`), cor vermelha mantida.
- Exportar → só ícone (`i-lucide-arrow-right-left`) + `v-tooltip` (já usa `v-tooltip` hoje,
  só remover o texto do botão).
- `KanbanRunMacroMenu` → remover a prop `show-label` (fica só ícone com tooltip, que já é o
  comportamento padrão do componente quando `showLabel` é `false`).

Manter Cancelar/Salvar como estão hoje (com label, grupo direito). Adicionar `flex-wrap`
no container `flex items-center justify-between` do rodapé como rede de segurança contra
overflow residual em telas muito estreitas.

## 4. Mover o bloco "Conversa vinculada" para entre Contato e Assignee

**Arquivo:** `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue`.

Hoje o bloco (`<div v-if="item.contact" class="p-3 bg-woot-50 dark:bg-woot-900/20
rounded-lg">`, linhas 523-560) é a última seção do corpo scrollável, depois de
Título/Valor/Etapa/Observações. Recortar o bloco inteiro (os dois branches — com
`item.conversation_id` e o `TagInput` de busca sem conversa vinculada — precisam mover
juntos, sem duplicar nem deixar branch órfã) e colar entre o fim do bloco de contato (hoje
linha 320) e o início do bloco de Assignee (hoje linha 322).

Nenhuma mudança de lógica/estado nesta etapa — é só reordenação de template. A lógica de
script (`contactConversations`, `conversationMenuItems`, `onSelectConversation`,
`clearConversation`, `linkedConversationUrl`, `openLinkedConversation`, watcher de
`item.contact.id`) permanece exatamente como está.

## 5. Botão "Ver Conversa" mais claro

**Arquivo:** mesmo bloco do item 4, branch `v-if="item.conversation_id"` (hoje linhas
532-550).

Trocar o link discreto `<a href="#" @click.prevent="openLinkedConversation">#{{
item.conversation_id }}</a>` por: o número da conversa como texto simples (não mais link) +
um botão `ButtonV4` (`app/javascript/dashboard/components-next/button/Button.vue`) explícito:

```vue
<div class="flex items-center justify-between gap-2">
  <span class="text-sm text-woot-700 dark:text-woot-300 truncate">
    #{{ item.conversation_id }}
  </span>
  <div class="flex items-center gap-1 flex-shrink-0">
    <ButtonV4
      size="xs"
      faded
      icon="i-lucide-external-link"
      :label="t('KANBAN.ITEM.CONVERSATION.VIEW')"
      @click="openLinkedConversation"
    />
    <button
      class="p-1 text-slate-400 hover:text-red-500 transition-colors"
      :title="t('KANBAN.ITEM.CONVERSATION.CLEAR')"
      @click="clearConversation"
    >
      <span class="i-lucide-x size-4" />
    </button>
  </div>
</div>
```

`openLinkedConversation(e)` já recebe o `MouseEvent` e trata `cmd/ctrl+click` para abrir em
nova aba (linhas 105-116 atuais) — o handler não muda, só o elemento que o dispara (de `<a>`
para `ButtonV4`). Confirmar no QA manual que o `cmd/ctrl+click` continua funcionando com o
botão.

Importar `ButtonV4` no `<script setup>` de `KanbanCardDetail.vue`:
```js
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
```

## QA manual

- Abrir um card com conversa vinculada e outro sem (branch `TagInput`) — confirmar
  posicionamento entre contato e assignee nos dois casos.
- Abrir o dropdown de "Rodar macro" no rodapé do detalhe (ícone só) e no cabeçalho da coluna
  (`KanbanColumn.vue`, já era ícone só) — confirmar que ambos continuam funcionando, e que o
  spinner por item aparece durante a execução.
- Testar o painel em janela estreita — confirmar que nenhum botão do rodapé estoura/sobrepõe
  Cancelar/Salvar.
- Testar dark mode — confirmar legibilidade do `DropdownMenu` (tokens `n-*`) dentro do
  contexto do painel (paleta `slate`).
- Testar `cmd/ctrl+click` no botão "Ver Conversa" (deve abrir em nova aba).
- `pnpm eslint:fix` nos arquivos tocados.

## Critério de pronto

- Rodapé do card não estoura nem sobrepõe em `max-w-md`.
- `KanbanRunMacroMenu.vue` usa `DropdownMenu` do design system, com a mesma API pública de
  props, funcionando nos dois pontos de entrada (`KanbanCardDetail.vue` e `KanbanColumn.vue`).
- Bloco "Conversa vinculada" posicionado entre Contato e Assignee.
- Botão "Ver Conversa" visível e funcional (incluindo `cmd/ctrl+click`), com i18n em `en` e
  `pt_BR`.
- `pnpm eslint:fix` limpo nos arquivos tocados.
