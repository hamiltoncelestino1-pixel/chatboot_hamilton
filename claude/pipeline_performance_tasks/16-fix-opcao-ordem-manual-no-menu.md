# Task 16 — Fix: não existe opção "ordem manual" no menu de ordenação

Severidade: 🟠 Alta. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

A task 03 trocou a ordenação padrão do board para `position` (ordem manual de arrasto), mas o
menu de ordenação não ganhou a opção correspondente:

```js
// KanbanSortMenu.vue:21-26
const sortMenus = computed(() => [
  { label: t('KANBAN.SORT.OPTIONS.ASSIGNEE'), value: 'assignee' },
  { label: t('KANBAN.SORT.OPTIONS.CREATED_AT'), value: 'created_at' },
  { label: t('KANBAN.SORT.OPTIONS.UPDATED_AT'), value: 'updated_at' },
  { label: t('KANBAN.SORT.OPTIONS.VALUE'), value: 'value' },
]);

const activeSortLabel = computed(
  () => sortMenus.value.find(m => m.value === activeSort.value.field)?.label || ''
);
```

Três efeitos:

1. **Rótulo vazio no estado padrão.** Com `activeSort.field === 'position'` o `find` não acha
   nada e o `SelectMenu` (`KanbanSortMenu.vue:86-91`) recebe `:label=""` — o agente abre o menu
   de ordenação e o campo "Ordenar por" aparece em branco.
2. **Caminho sem volta.** Depois que o agente escolhe qualquer ordenação, não há opção para
   voltar à ordem manual. E como `isSortActive` passa a ser `true`, o `onEnd` de
   `KanbanColumn.vue:76-79` cancela o arrasto — **arrastar para reordenar fica desativado de
   forma permanente**, sem nenhuma indicação de como reverter. A escolha é persistida por
   pipeline em `useUISettings` (`setKanbanBoardSettings`, `KanbanSortMenu.vue:44-46`), então
   sobrevive a reload e troca de máquina.
3. **Agentes já caem nesse estado hoje.** Quem usou o board antes desta mudança tem
   `{ field: 'created_at', order: 'desc' }` (o default antigo) salvo em `useUISettings`. O
   watcher de `KanbanIndex.vue:38` restaura esse valor no primeiro load, então para esses
   usuários o board já abre com ordenação explícita e o arrasto já nasce desativado.

## O que corrigir

1. Acrescentar a opção `position` a `sortMenus`, como primeira da lista (é o default), com
   chave de i18n nova em `KANBAN.SORT.OPTIONS` — algo como `MANUAL`/"Ordem manual" /
   "Manual order". Domínio Kanban mantém `pt_BR` sincronizado com `en` (exceção documentada no
   `AGENTS.md`), então **os dois arquivos** (`i18n/locale/en/kanban.json` e
   `i18n/locale/pt_BR/kanban.json`).
2. Conferir que `order` (asc/desc) continua fazendo sentido com `position` selecionado — o
   backend aceita as duas direções (`pipeline_item_finder.rb:90`), então "ordem manual
   descendente" é um estado válido mas provavelmente sem utilidade. Decidir: ou esconder o
   seletor de direção quando o campo é `position`, ou deixar como está e documentar. Não deixar
   ambíguo.
3. Revisar o texto de `KANBAN.FILTER.DISABLE_DRAG_HINT` (`KanbanColumn.vue:99-101`) — hoje ele
   explica que o arrasto está desativado, mas agora existe uma ação concreta para reverter
   ("volte para Ordem manual"), e o tooltip deve dizer isso.
4. Decidir o que fazer com a preferência antiga salva (efeito 3): migrar quem tem
   `created_at/desc` salvo para `position/asc` significaria descartar uma escolha que pode ter
   sido deliberada. O caminho mais honesto é **não migrar** e apenas garantir que o agente
   consegue voltar sozinho pela opção nova — mas isso é decisão de produto, confirmar antes.

## Testes

1. Board recém-aberto (sem preferência salva): o campo "Ordenar por" mostra "Ordem manual", não
   um rótulo vazio.
2. Escolher "Valor", confirmar que o arrasto para reordenar é cancelado; voltar para "Ordem
   manual" e confirmar que o arrasto **volta a funcionar** (depende da task 15 estar feita para
   o efeito ser visível).
3. Recarregar a página em cada um dos dois estados e confirmar que a preferência persistiu.
4. Simular o cenário do agente antigo: gravar `{ field: 'created_at', order: 'desc' }` em
   `useUISettings` para um pipeline, recarregar, e confirmar que ele consegue voltar para ordem
   manual pelo menu.
5. Tema escuro e tela estreita — o item novo no `SelectMenu` não pode quebrar o layout.

## Decisões registradas (2026-09-16)

- **Item 2 (direção com `position`)**: seletor de "Direção" escondido quando o campo é `position`
  (`KanbanSortMenu.vue`, `v-if="!isManualOrder"`). Selecionar "Ordem manual" sempre força
  `order: 'asc'`, independente do que estava selecionado antes — não existe estado "manual
  descendente" alcançável pela UI.
- **Item 4 (preferência antiga)**: **não migrada**, como o próprio documento recomendava. Quem
  já tinha `{ field: 'created_at', order: 'desc' }` salvo continua vendo essa ordenação até
  escolher "Ordem manual" no menu — a opção nova é suficiente pra ele voltar sozinho, e migrar
  descartaria uma escolha que pode ter sido deliberada.
- **Achado adicional durante a implementação**: o fallback usado quando não há preferência
  salva (`DEFAULT_KANBAN_BOARD_SETTINGS.sort` em `useUISettings.js`) ainda estava em
  `{ field: 'created_at', order: 'desc' }`, desatualizado desde a task 03 (que mudou o default
  real para `position`/`asc` só em `store/modules/kanban/constants.js`). Sem corrigir isso, um
  pipeline **novo, sem preferência salva**, continuaria abrindo com "Criado em" selecionado em
  vez de "Ordem manual" (teste 1 do critério de pronto não passaria) — corrigido para bater com
  `DEFAULT_KANBAN_SORT`.

## Critério de pronto

- `position` é uma opção visível e selecionável no menu, e é o rótulo mostrado no estado padrão.
- Dá para voltar à ordem manual (e, portanto, reabilitar o arrasto) sem limpar `localStorage`.
- Chaves novas em `en/kanban.json` **e** `pt_BR/kanban.json`.
- Decisão sobre a preferência antiga registrada neste arquivo.
- `pnpm eslint` limpo (atenção a `vue/no-bare-strings-in-template`).

## Resultado (registrado em 2026-09-21, implementado e verificado na auditoria de 2026-09-18)

As decisões de produto dos itens 2 e 4 e o achado do fallback estão em "Decisões registradas"
acima; este bloco fecha o resto e reconfere contra o código:

1. **Item 1** - `position` é a primeira opção de `sortMenus` (`KanbanSortMenu.vue:22`,
   `KANBAN.SORT.OPTIONS.MANUAL`), traduzida em `en` ("Manual order") e `pt_BR` ("Ordem manual").
2. **Item 2** - o seletor de direção some com `v-if="!isManualOrder"` (`KanbanSortMenu.vue:100`) e
   `handleSortChange` força `asc` ao entrar em `position` (`:54`): "manual descendente" não é um
   estado alcançável pela UI (o backend continua aceitando `desc` por API).
3. **Item 3** - `KANBAN.FILTER.DISABLE_DRAG_HINT` reescrito nos dois idiomas para apontar a ação
   ("Volte para Ordem manual para arrastar e reordenar os cards" / "Switch back to Manual order to
   drag and reorder cards").
4. **Item 4** - preferência antiga **não migrada**: `DEFAULT_KANBAN_BOARD_SETTINGS.sort` em
   `useUISettings.js` mudou de `{ created_at, desc }` (no HEAD) para `{ position, asc }`, o que só
   vale para pipeline sem preferência salva; quem tinha `created_at/desc` gravado continua com ele
   e volta à ordem manual pelo menu. Era exatamente a pergunta de produto em aberto; a escolha foi
   a recomendada pelo próprio arquivo.
