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

## Resultado (2026-10-05)

### No escopo da task

`AutomationActionCreatePipelineItemTaskInput.vue`:

```js
due_in_days: dueInDays.value === '' ? null : dueInDays.value,  // updateValue
dueInDays.value = data.due_in_days ?? '';                      // onMounted
```

O `Input.vue` já converte para número de verdade quando `type="number"` e o valor não é vazio
(`Number(value)`, `components-next/input/Input.vue:65-67`), então `dueInDays.value` é sempre
`''` ou um `Number` — a comparação com `''` cobre exatamente o caso de "campo vazio" sem
confundir com `0`.

### Dois achados adjacentes, incluídos com aprovação do usuário

**(a) O `min="0"` desse input era inerte.** `Input.vue` só repassava `min` para o DOM quando o
tipo era `date`/`datetime-local`/`time` (linha 134) — `number` estava na lista do `max` (linha
136) mas **não** na do `min`. E como `min` é declarado como prop, não cai no `v-bind="$attrs"`
tampouco. Resultado: era possível digitar `-5`, e `(-5).days.from_now` cria uma task já nascida
vencida. Corrigido acrescentando `'number'` à lista do `min`.

Isso importava porque **a premissa desta task é que o `min="0"` sinaliza que `0` é válido** — o
atributo que justifica a task não estava chegando ao DOM.

Raio de impacto medido antes de mexer num componente compartilhado por **56** consumidores: dos
6 que usam `type="number"`, **só este** passa `min`. (O `FairDistribution.vue` também passa
`min`, mas para o `DurationInput`, outro componente; os dois outros consumidores de `min` no
`Input.vue` são `datetime-local`, já cobertos pela lista antiga.) A mudança altera o
comportamento de **exatamente um** input no app.

**(b) Mesmo bug de falsy no componente irmão.**
`AutomationActionCreatePipelineItemInput.vue` fazia `value.value || null` e `data.value || ''` —
um card com valor `0` salvava como `null` e reabria em branco. Corrigido com a mesma expressão
(`=== ''` / `??`). Fora do escopo nominal da task, que cita só `due_in_days`.

### Verificação incidental da task 17

Ao rastrear o formato de `action_params` aqui, confirmei que `actionQueryGenerator` embrulha o
objeto num array ao salvar (`[{title, due_in_days}]`), mas `manifestActions` **desembrulha** de
volta para objeto plano ao abrir a edição (`useEditableAutomation.js:106-111`, `params[0] || {}`).
Ou seja, a validação da task 17 (`action.action_params?.title?.trim()`) está correta tanto na
criação quanto na edição — **sem falso positivo** ao editar uma regra que já tem título.

### Verificação empírica

Spec temporário (`tmp_task18_debug.spec.js`, apagado depois) montando o componente de verdade
(`mount`, não `shallowMount`, para exercitar o `Input.vue` real):

**Com os fixes:**

```
  typed 0          -> {"title":"Ligar","due_in_days":0}
  cleared          -> {"title":null,"due_in_days":null}
  reopened with 0  -> input value = 0
  reopened with 5  -> input value = 5
  min attribute    = "0"
5 passed
```

**Com os fixes revertidos:**

```
  typed 0          -> {"title":"Ligar","due_in_days":null}   <- o 0 digitado virou null
  cleared          -> {"title":null,"due_in_days":null}
  reopened with 0  -> input value =                          <- campo em branco
  reopened with 5  -> input value = 5
  min attribute    = undefined                               <- min inerte
3 failed | 2 passed
```

`cleared` e `reopened with 5` idênticos nas duas execuções: os caminhos normais (campo vazio
continua virando `null`, valor comum continua aparecendo) não regrediram.

**Nota de honestidade sobre a cobertura:** o componente irmão do item (b) **não** foi montado em
spec — ele depende do store Vuex e do `usePipelineSelector`, e a mudança é a mesma expressão de
duas linhas já provada empiricamente no componente desta task. A verificação dele fica no teste
manual.

**Lint:** `eslint` exit 0 e `prettier --check` limpo nos 3 arquivos. Nenhum CRLF introduzido
nesta task.
