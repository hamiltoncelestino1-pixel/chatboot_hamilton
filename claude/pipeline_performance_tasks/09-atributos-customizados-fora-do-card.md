# Task 09 — `getAttributesByModel` recalculado uma vez por card

Severidade: 🟡 Média. Achado na análise de performance de 2026-09-15.
Independente das demais — pode ser feita a qualquer momento.

## Objetivo

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCard.vue:31-33`:

```js
const pipelineItemAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('pipeline_item_attribute')
);
```

E `app/javascript/dashboard/store/modules/attributes.js:33-37`:

```js
getAttributesByModel: _state => attributeModel => {
  return _state.records.filter(
    record => record.attribute_model === attributeModel
  );
},
```

Mesmo problema estrutural da task 08, em escala menor: é um getter *method-style* (Vuex não
cacheia), que faz `.filter()` sobre **todos** os atributos customizados da conta, e é invocado
**por card renderizado**. Com 200 cards na tela e 30 atributos na conta, são 6.000 comparações
a cada invalidação — e o `computed` de cada card é invalidado sempre que o store de atributos
muda, ou quando o card remonta (o que, antes da task 08, acontece o tempo todo).

O resultado é idêntico para todos os cards do board: a lista de atributos do modelo
`pipeline_item_attribute` não depende do card. Só o `visibleAttributes` (linhas 55-67) é que é
por card, porque lê `props.item.custom_attributes`.

## O que corrigir

1. Calcular `pipelineItemAttributes` **uma vez** — no `KanbanIndex.vue` ou no `KanbanBoard.vue`
   — e passar por prop até `KanbanCard.vue`. O board já passa props pela cadeia
   `KanbanBoard → KanbanColumn → KanbanCard`, então é o caminho natural; alternativa mais
   limpa se a cadeia incomodar: `provide`/`inject` no board (o projeto já usa esse padrão em
   `ConversationList.vue:30,55`).
2. Filtrar por `display_on_card` (linha 57) também uma vez só — o filtro não depende do card,
   só o valor depende. O card fica apenas com o `.map()` que lê
   `props.item.custom_attributes?.[attr.attribute_key]`.
3. `store.dispatch('attributes/get')` já é disparado em `KanbanIndex.vue:52`, então não há
   request novo.

## Testes

1. Board com cards que tenham atributos customizados marcados como `display_on_card` e outros
   não: os atributos exibidos no card continuam exatamente os mesmos, na mesma ordem.
2. Criar/editar/apagar um atributo customizado de `pipeline_item` em Configurações e voltar ao
   board: a mudança reflete nos cards (a reatividade não pode ser perdida ao subir o cálculo).
3. Card sem nenhum atributo preenchido continua sem a seção (linha 147, `v-if`).

## Critério de pronto

- `getAttributesByModel('pipeline_item_attribute')` chamado uma vez por board, não uma por card.
- Atributos no card idênticos antes e depois, e ainda reativos a mudanças em Configurações.
- `pnpm eslint` limpo (props em runtime, não TS — `vue/define-props-declaration: runtime`).
