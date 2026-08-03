# Task 20 — Filtro por etiqueta no Kanban

Task de UI, independente das demais tasks do épico. Escopo: adicionar um filtro por etiqueta
(label) ao popover de filtros do board do Kanban (`KanbanFilterBar.vue`), que hoje tem
Responsável, Data de criação, Data de atualização e Valor min/max, mas não tem etiqueta —
lacuna identificada depois de fechar a task 19.

Nenhum código Ruby/backend precisa ser tocado: a filtragem do board já é 100% client-side
sobre os itens já carregados no state Vuex (`kanban/actions.js#fetchItems` carrega todos os
itens do pipeline de uma vez, e cada `pipeline_item` já vem com `label_list` populado no
payload — `app/views/api/v1/models/_pipeline_item.json.jbuilder:30`). Não se aplica
sincronização com `enterprise/`. Não escrever specs novas nesta task (regra do projeto); os
specs existentes de `store/modules/kanban/specs/getters.spec.js` continuam passando sem
alteração porque usam `{ ...DEFAULT_KANBAN_FILTERS, campo: valor }` e nunca hardcodam o shape
completo do objeto de filtros.

## 1. `store/modules/kanban/constants.js` — nova chave de filtro

**Arquivo:** `app/javascript/dashboard/store/modules/kanban/constants.js`

```js
export const DEFAULT_KANBAN_FILTERS = Object.freeze({
  assigneeId: null,
  createdAtRange: null,
  updatedAtRange: null,
  valueRange: null,
  labelTitles: null,
});
```

`isFilterActive`/`isBoardFiltered` (`store/modules/kanban/getters.js:46-57`) **não precisam de
mudança** — já iteram genericamente sobre `Object.keys(DEFAULT_KANBAN_FILTERS)`, então a chave
nova é coberta automaticamente. `SET_KANBAN_FILTERS`/`RESET_KANBAN_FILTERS`
(`store/modules/kanban/mutations.js:4-10`) também já fazem merge/reset genérico — nenhuma
mudança necessária ali.

## 2. `store/modules/kanban/getters.js` — filtrar por `label_list`

**Arquivo:** `app/javascript/dashboard/store/modules/kanban/getters.js`,
`getFilteredSortedItemsForStage` (hoje linhas 59-89).

Adicionar `labelTitles` à desestruturação de `$state.activeFilters` (linha 62-63) e um novo
bloco de filtro, com **semântica OR** (item aparece se tiver PELO MENOS UMA das etiquetas
selecionadas) — mesmo padrão já usado no backend do Chatwoot para conversas
(`app/finders/conversation_finder.rb:175-178`, `tagged_with(params[:labels], any: true)`):

```js
if (labelTitles?.length) {
  items = items.filter(i =>
    (i.label_list || []).some(title => labelTitles.includes(title))
  );
}
```

Inserir junto aos outros blocos de filtro (`assigneeId`, `createdAtRange`, `updatedAtRange`,
`valueRange`), antes da ordenação final.

## 3. `composables/useUISettings.js` — manter os dois defaults sincronizados

**Arquivo:** `app/javascript/dashboard/composables/useUISettings.js`,
`DEFAULT_KANBAN_BOARD_SETTINGS.filters` (hoje linhas 135-144).

Esse objeto é uma cópia duplicada, mantida à mão, do shape de `DEFAULT_KANBAN_FILTERS` (mesma
dívida já documentada no item 4 da task 17 deste épico, mas em outro par de arquivos). Não é
estritamente necessário para o filtro funcionar — `SET_KANBAN_FILTERS` faz merge e não apaga a
chave nova mesmo se ausente aqui — mas para não deixar os dois defaults divergirem, adicionar:

```js
const DEFAULT_KANBAN_BOARD_SETTINGS = {
  filters: {
    assigneeId: null,
    createdAtRange: null,
    updatedAtRange: null,
    valueRange: null,
    labelTitles: null,
  },
  ...
};
```

## 4. `KanbanFilterBar.vue` — novo bloco "Etiquetas" no popover

**Arquivo:** `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanFilterBar.vue`

Reaproveitar o componente já usado para atribuir etiquetas ao card,
`shared/components/ui/label/LabelDropdown.vue` (`accountLabels`, `selectedLabels`,
`allowCreation`, eventos `@add`/`@remove`), no mesmo padrão trigger-botão + painel absoluto já
implementado em `PipelineItemLabels.vue:67-98` (`v-on-clickaway`, `relative`, painel `absolute
top-full ... z-[9999]`).

- Alimentar com `labels/getPipelineLabels` (getter já filtrado para `label_type ===
  'pipeline_label'`, mesmo usado em `PipelineItemLabels.vue:13` e validado no backend em
  `pipeline_item.rb#labels_must_be_pipeline_type`) — **não usar** o getter genérico de todas
  as labels da conta.
- `selected-labels="activeFilters.labelTitles || []"`.
- `@add`/`@remove` atualizam o array local e chamam `applyFilter({ labelTitles: updated })`
  (mesma função `applyFilter` já usada pelos outros controles do popover, linha 34-37).
- Inserir o bloco novo dentro do popover (`div v-if="isOpen"`, hoje linhas 104-236), antes do
  botão "Limpar filtros" (linha ~230).
- **Atenção ao z-index/overflow**: o popover de filtros já é um painel `absolute z-40` com
  `overflow-hidden` no container (linha 107). Empilhar o `LabelDropdown` (que abre com
  `z-[9999]`) dentro desse painel pode ficar cortado pelo `overflow-hidden` do pai — testar
  visualmente e, se necessário, remover/ajustar esse `overflow-hidden` ou renderizar o
  `LabelDropdown` via `Teleport`.

## 5. i18n — nova(s) chave(s) em `KANBAN.FILTER`

**Arquivos:** `app/javascript/dashboard/i18n/locale/en/kanban.json` e
`pt_BR/kanban.json`, bloco `FILTER` (hoje linhas 54-67 — domínio Kanban mantém `pt_BR`
sincronizado manualmente, os dois precisam ser tocados juntos).

Adicionar, ao lado de `VALUE_LABEL`/`MIN`/`MAX`:
```json
"LABEL_LABEL": "Labels",
"LABEL_PLACEHOLDER": "Filter by label..."
```
(pt_BR: `"LABEL_LABEL": "Etiquetas"`, `"LABEL_PLACEHOLDER": "Filtrar por etiqueta..."`)

## QA manual

- Aplicar o filtro com 1 etiqueta e confirmar que só os cards com aquela etiqueta aparecem.
- Aplicar com 2+ etiquetas e confirmar semântica **OR** (card com qualquer uma delas aparece,
  não precisa ter todas).
- Combinar com outro filtro já existente (ex. Responsável + Etiqueta) e confirmar que os dois
  se aplicam juntos (AND entre filtros diferentes, OR dentro do mesmo filtro de etiqueta).
- Confirmar que a bolinha de "filtro ativo" acende com etiqueta selecionada.
- Clicar em "Limpar filtros" e confirmar que a seleção de etiquetas também é resetada.
- Trocar de pipeline e voltar — confirmar que o filtro de etiqueta persiste (via
  `kanban_board_settings` em UI settings).
- Testar visualmente o empilhamento do `LabelDropdown` dentro do popover (risco de
  overflow/z-index) em dark mode e light mode.
- `pnpm eslint:fix` nos arquivos tocados.
- Rodar `store/modules/kanban/specs/getters.spec.js` (Vitest) para confirmar que os testes
  existentes de `getFilteredSortedItemsForStage`/`isBoardFiltered` continuam passando.

## Critério de pronto

- Filtro por etiqueta funcional no popover do Kanban, com semântica OR entre etiquetas
  selecionadas.
- Badge de "filtro ativo" e "Limpar filtros" cobrem a etiqueta automaticamente.
- Filtro persiste por pipeline via `kanban_board_settings`.
- i18n completo em `en` e `pt_BR`.
- Specs existentes de `store/modules/kanban/specs/getters.spec.js` continuam passando.
- `pnpm eslint:fix` limpo nos arquivos tocados.
