# Task 18 — Fix: `due_in_days = 0` tratado como falsy no formulário de automação

Severidade: 🟢 Baixa. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/javascript/dashboard/components/widgets/AutomationActionCreatePipelineItemTaskInput.vue:16,23`:

```js
due_in_days: dueInDays.value || null,      // linha 16 (updateValue)
dueInDays.value = data.due_in_days || '';  // linha 23 (onMounted)
```

O input tem `min="0"` (linha ~40), implicando que `0` ("vence hoje") é um valor válido de
input, mas `x || y` trata `0` como falsy: digitar `0` no campo grava `null` em vez de `0`, e
reabrir uma regra cujo `due_in_days` tenha sido persistido como `0` por outro caminho (ex. via
API diretamente) mostraria o campo em branco em vez de `0`.

Hoje isso é funcionalmente inofensivo porque o backend trata `nil` igual a `0`
(`attrs[:due_in_days].to_i.days.from_now`, `app/services/concerns/pipeline_item_actions.rb:52`
— `nil.to_i` é `0`), mas o bug de round-trip/exibição é real e volta a morder se esse default
do backend mudar no futuro.

## O que corrigir

Trocar `dueInDays.value || null` por uma checagem explícita que não trate `0` como ausência de
valor — ex. `dueInDays.value === '' ? null : dueInDays.value`. Mesmo ajuste no sentido inverso
(linha 23, `onMounted`): `data.due_in_days ?? ''` em vez de `data.due_in_days || ''`.

## Testes

Testar manualmente: configurar a ação "criar task" com `due_in_days = 0`, salvar, reabrir a
automação — o campo deve mostrar `0`, não aparecer em branco.

## Critério de pronto

- Digitar/persistir `0` no campo "dias para vencer" funciona corretamente no round-trip
  (salvar e reabrir mostra `0`, não vazio).
- `pnpm eslint:fix` limpo no arquivo tocado.
