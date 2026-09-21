# Task 26 — Fix: alertas de falha do board em inglês hardcoded

Severidade: 🟡 Média. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).

## Objetivo

A [task 21](21-fix-resetboard-sem-tratamento-de-erro.md) pedia chaves de i18n para o estado de
erro. As strings **da coluna** foram traduzidas certinho (`KANBAN.COLUMN.ERROR` e
`KANBAN.COLUMN.RETRY`, presentes em `en/kanban.json` e `pt_BR/kanban.json`), mas as duas do
alerta agregado ficaram de fora — `app/javascript/dashboard/store/modules/kanban/actions.js`:

```js
const failedCount = stageIds.filter(
  stageId => state.stageItems[stageId]?.hasError
).length;
if (failedCount === 1) {
  useAlert('A column failed to load. Try again from that column.');
} else if (failedCount > 1) {
  useAlert(
    `${failedCount} columns failed to load. Try again from each column.`
  );
}
```

O resultado registrado na task 21 justifica isso como "mesmo padrão de string simples sem `t()`
já usado nas outras chamadas de `useAlert` deste arquivo" — e é verdade, `moveItem`,
`reorderStages` e `reorderItems` também têm string crua em inglês. Mas isso é um bug
pré-existente do módulo replicado, não um padrão a preservar: o produto é pt_BR e o agente lê
inglês na tela.

`app/javascript/dashboard/store/modules/kanban/actions.js` já importa de `dashboard/composables`,
e há precedente de i18n dentro de arquivo Vuex neste projeto (o próprio módulo kanban importa
`useAlert` direto, e outros módulos usam `useI18n`/`i18n.global.t` em actions) — conferir qual
forma o resto do `store/modules/` usa antes de escolher, em vez de inventar uma.

## O que corrigir

1. Chaves novas em `KANBAN.BOARD` (ou `KANBAN.COLUMN`, seguir o namespace que fizer mais sentido
   junto das que já existem), com pluralização para o caso de N colunas — `vue-i18n` suporta
   plural com `|`, e o projeto já usa interpolação com contagem em
   `KANBAN.RUN_MACRO.COLUMN_ITEM_LABEL` e `KANBAN.ITEM.OVERDUE_TASKS_TOOLTIP`.
2. Traduzir em `en/kanban.json` **e** `pt_BR/kanban.json` — domínio Kanban é a exceção documentada
   no `AGENTS.md` que mantém os dois sincronizados.
3. Aproveitar e traduzir as outras três strings cruas do mesmo arquivo (`'Failed to move card...'`,
   `'Failed to reorder stages...'`, `'Failed to reorder cards...'`). São do mesmo módulo, do mesmo
   tipo, e deixar metade traduzida é pior que o estado atual. Se isso fizer a task crescer demais,
   separar — mas não deixar sem decisão.

## Testes

1. Com o idioma do agente em pt_BR, bloquear o endpoint de uma stage no DevTools e recarregar o
   board: o alerta agregado aparece **em português**.
2. Bloquear duas stages e confirmar o plural correto (e que o número aparece).
3. Trocar o idioma para inglês e repetir — as duas formas corretas.
4. Forçar falha no arrastar entre colunas e no reordenar (item 3 do "O que corrigir") e conferir
   os alertas.
5. Conferir que nenhuma chave nova ficou só em `en`.

## Critério de pronto

- Nenhuma string de UI crua em `store/modules/kanban/actions.js`.
- Chaves novas presentes em `en/kanban.json` **e** `pt_BR/kanban.json`, com plural tratado.
- `pnpm eslint` limpo.

## Resultado (2026-09-19)

**A premissa do texto da task não se confirmou.** Ela dizia que "outros módulos usam
`useI18n`/`i18n.global.t` em actions". Conferi: há **zero** uso de i18n em qualquer arquivo de
`store/` (fora specs), e a instância do `vue-i18n` era criada inline em
`entrypoints/dashboard.js`, sem ser exportada — uma action não tinha como traduzir. Não havia
forma existente a seguir, então precisei introduzir uma, a menor possível.

**Mudança de infraestrutura (pequena, mas fora do módulo kanban):** nova
`app/javascript/dashboard/i18n/instance.js` exporta a instância única (`createI18n` com as
mesmas opções de antes), e `entrypoints/dashboard.js` passou a importá-la em vez de criar inline
(saíram os imports `createI18n`/`i18nMessages`, que ficaram sem uso). É a **mesma** instância
que o app instala, então acompanha as trocas de `$root.$i18n.locale`. Vale uma olhada de quem
revisar por tocar o bootstrap do dashboard.

`actions.js`: as 4 strings cruas viraram `i18n.global.t(...)` — alerta agregado do `resetBoard`
(com plural: `t(key, { count }, count)`, formas separadas por `|`) e as três do mesmo arquivo
(`moveItem`, `reorderStages`, `reorderItems`), feitas junto como o item 3 pedia. Chaves em
`KANBAN.BOARD.*` (`COLUMNS_LOAD_FAILED`, `MOVE_ITEM_FAILED`, `REORDER_STAGES_FAILED`,
`REORDER_ITEMS_FAILED`), presentes em `en` **e** `pt_BR` com as mesmas 4 chaves (conferido por
script).

Validado na aplicação real (forcei falha de XHR nas requests e li o toast renderizado):
- pt_BR, 1 coluna: "Uma coluna não carregou. Tente de novo na própria coluna."
- pt_BR, 2 colunas: "2 colunas não carregaram. Tente de novo em cada uma."
- en (trocando `$i18n.locale` em runtime), 1 e 2 colunas: as duas formas corretas, com o número.
- mover card / reordenar etapas / reordenar cards com falha forçada: os 3 alertas saem em
  `en` e em `pt_BR`.
Nenhuma request real bloqueada permaneceu; nenhum dado de banco foi alterado.

`pnpm eslint`: 0 erros. `pnpm vitest` (kanban): 23/23 — o spec de actions passou a carregar a
instância do i18n e continua verde.

**Fora do escopo, não tocado:** outros módulos do `store/` (e componentes) podem ter strings
cruas parecidas — só verifiquei `kanban/actions.js`, que é o critério da task.
