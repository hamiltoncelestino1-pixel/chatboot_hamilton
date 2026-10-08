# Task 06 — Fix: `handleSave` reporta sucesso mesmo quando o move falhou ou foi cancelado

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).
Depende da task 02 (mesmo fluxo de `kanban/moveItem` + prompt de lost reason).

## Objetivo

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue:201-225`
(`handleSave`):

```js
const handleSave = async () => {
  try {
    // ...
    if (form.value.pipeline_stage_id !== props.item.pipeline_stage_id) {
      await store.dispatch('kanban/moveItem', { /* ... */ });   // linha ~211
    }
    await store.dispatch('kanban/updateItem', payload);          // linha ~219
    useAlert(t('KANBAN.ITEM.API.UPDATE_SUCCESS'));                // linha ~220
    emit('close');
    // ...
```

`kanban/moveItem` (`store/modules/kanban/actions.js`) **nunca lança exceção** — nem quando o
usuário cancela o modal de motivo de perda (`rollback(); return;`), nem quando a API falha
(`catch { rollback(); useAlert(...); }` interno). `handleSave` não tem como saber que o move
foi revertido, então continua o `try` normalmente.

**Cenário 1 (cancelamento)**: usuário troca o dropdown "Stage" pra um estágio `lost` e clica
"Save". O modal de motivo abre; o usuário clica "Cancel". `moveItem` reverte o card
silenciosamente (comportamento correto do `moveItem` em si), mas `handleSave` segue adiante,
chama `updateItem` (salvando título/valor/notas normalmente), mostra
`KANBAN.ITEM.API.UPDATE_SUCCESS` e fecha o painel — como se a mudança de estágio tivesse sido
aplicada, quando na verdade só os outros campos foram salvos.

**Cenário 2 (falha de API no move)**: o usuário vê dois toasts contraditórios em sequência —
"Failed to move card. Please try again." (de dentro de `moveItem`) seguido imediatamente de
"Item updated successfully." (de `handleSave`).

## O que corrigir

`kanban/moveItem` precisa comunicar pro chamador se o move foi de fato aplicado, cancelado, ou
falhou — opções:
1. Fazer `moveItem` retornar um valor (`true`/`false`, ou lançar exceção só no caso de
   cancelamento/falha) que `handleSave` possa checar antes de prosseguir pro `updateItem`.
2. `handleSave` checa esse retorno e, se o move não foi aplicado, não segue pro `updateItem`
   automaticamente com o `pipeline_stage_id` antigo — ou trata o restante do save
   separadamente do resultado do move, evitando o toast de sucesso indevido.

Manter o comportamento de `rollback()` interno do `moveItem` como está (já é o padrão correto
de UI otimista do resto do Kanban) — o fix é só garantir que `handleSave` não afirme sucesso
quando uma parte do que tentou salvar não foi.

## Testes

Testar manualmente:
- Mudar o stage pra um estágio `lost` no painel do card, cancelar o modal de motivo — o painel
  não deve fechar com toast de sucesso indicando que o stage mudou.
- Simular falha de API no move (ex. desconectar rede momentaneamente) — não deve aparecer o
  toast de "Item updated successfully" logo depois do toast de erro.

## Critério de pronto

- Cancelar o modal de motivo de perda durante o save não gera toast de sucesso indevido.
- Falha de API no move não é seguida por um toast de sucesso contraditório.
- Salvar título/valor/notas sem trocar de estágio continua funcionando exatamente como antes.
- `pnpm eslint:fix` limpo nos arquivos tocados.

## Decisão e resultado (2026-09-29)

**Saída 1 da task** (`moveItem` comunica o resultado pelo retorno), com a decisão de produto que
a task deixava em aberto resolvida assim: quando o move não é aplicado, **o save inteiro é
abortado**, em vez de persistir título/valor/notas mesmo assim. Salvar parte do que o usuário
pediu e anunciar sucesso é o mesmo defeito que a task quer eliminar, só que em outra forma.
Como não há `emit('close')` nesse caminho, o painel fica aberto com as edições intactas no
formulário — o usuário ajusta o estágio (ou escolhe um motivo) e salva de novo, sem perder nada.

**`moveItem`** (`store/modules/kanban/actions.js`): `return false` no cancelamento do prompt e no
`catch` da falha de API, `return true` depois do `commit('EDIT_ITEM')`. O `rollback()` interno e
os toasts próprios ficaram exatamente como estavam (a task pedia para preservar). O contrato de
retorno foi documentado no comentário do action.

**`handleSave`** (`KanbanCardDetail.vue`): guarda `if (!moved) return;` logo após o dispatch.
Sem toast no cancelamento (é ação deliberada do usuário); na falha de API o único toast é o
`KANBAN.BOARD.MOVE_ITEM_FAILED` que o próprio `moveItem` já emite — o que mata o par de toasts
contraditórios do cenário 2.

**Mudança é aditiva:** o outro consumidor, `KanbanBoard.vue:47-54` (`handleCardMove`, o
drag-and-drop), faz `await` e ignora o retorno. Nada a alterar lá — o estado do board já está
correto nos dois desfechos por causa do rollback.

**Verificação:** `actions.spec.js` cobre **apenas** `applyRealtimePipelineItem` — nenhum dos 6
testes existentes toca `moveItem`, então o verde deles não dizia nada sobre esta mudança. Usei o
mesmo recurso da task 30 de `claude/pipeline_performance_tasks/`: spec Vitest temporário
(`tmp-move-item-contract.spec.js`, apagado depois) cobrindo os três desfechos de retorno.

- Com a correção: **3/3 passando**.
- Revertendo a correção por um instante: **3/3 falhando**, com
  `AssertionError: expected undefined to be true` / `to be false` — ou seja, o spec pega o bug de
  verdade, não passa por acidente.
- Suíte completa do módulo depois de restaurar: **26/26** (`getters` 17 + `actions` 6 + o
  temporário 3), e o temporário foi removido em seguida.

**ESLint:** 0 erros nos dois arquivos. Os 2 warnings restantes em `KanbanCardDetail.vue`
(`@intlify/vue-i18n/no-raw-text`, linhas 335 e 494) são pré-existentes e fora do diff —
confirmado que correspondem às linhas 330/489 do HEAD, deslocadas pelas 5 linhas adicionadas.

**Line endings:** conferido que os dois arquivos seguem em LF (`git ls-files --eol` → `i/lf w/lf`,
e inspeção de bytes com `od -c`). O aviso `LF will be replaced by CRLF` que o git imprime é o
`core.autocrlf=true` do Windows descrevendo um checkout futuro, não algo introduzido aqui —
`.gitattributes` fixa `eol=lf` só para `*.sh`, `docker/entrypoints/**`, `bin/*` e `*.rb`, então
`.js`/`.vue` seguem sem pin (situação pré-existente, herdada da task 22).
