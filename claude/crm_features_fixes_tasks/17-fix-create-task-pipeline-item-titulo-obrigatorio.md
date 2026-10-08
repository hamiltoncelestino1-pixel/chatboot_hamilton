# Task 17 — Fix: automação "criar task" sem título falha silenciosamente

Severidade: 🟢 Baixa. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/services/concerns/pipeline_item_actions.rb:46-57`:

```ruby
def create_task_for_pipeline_item(pipeline_item, attrs)
  assignee_id = attrs[:assignee_id].presence || pipeline_item.assignee_id
  log_missing_task_assignee(pipeline_item) if assignee_id.blank?

  pipeline_item.account.tasks.create!(
    title: attrs[:title],
    # ...
  )
end
```

Sem fallback nem validação prévia de `attrs[:title]`. No frontend,
`app/javascript/dashboard/components/widgets/AutomationActionCreatePipelineItemTaskInput.vue:13-18`
não marca o campo título como obrigatório no formulário.

**Efeito**: admin cria uma automação "criar task" sem preencher o título; `Task.create!` falha
por `validates :title, presence: true` (`app/models/task.rb:51`) e a exceção é engolida pelo
`rescue StandardError` genérico do `AutomationRules::PipelineActionService`/
`Macros::PipelineExecutionService` (mesmo padrão de todo o resto desses arquivos — não é uma
inconsistência nova). Efeito prático: a automação "roda" sem erro visível, mas nunca cria
nenhuma task.

## O que corrigir

Marcar o campo "title" como obrigatório em
`AutomationActionCreatePipelineItemTaskInput.vue` (validação de formulário no client, mesmo
nível de obrigatoriedade que outros campos required de ações de automação no projeto),
impedindo salvar a automação sem título preenchido. Não é necessário mudar o rescue genérico
do backend (mantém o padrão já estabelecido no arquivo) — o fix é evitar que a configuração
inválida seja salva, não tratar o erro em runtime.

## Testes

Testar manualmente: tentar salvar uma automação com a ação "criar task" sem preencher o
título — deve bloquear o salvamento com indicação de campo obrigatório, mesmo padrão visual
dos outros campos required do formulário de automação.

## Critério de pronto

- Não é possível salvar uma automação com ação "criar task" sem título preenchido.
- `pnpm eslint:fix` limpo no arquivo tocado.

## Resultado (2026-10-05)

### Correção ao texto desta task: o arquivo a mexer não era o componente

A task manda marcar o campo como obrigatório em
`AutomationActionCreatePipelineItemTaskInput.vue`. **O componente não tem influência alguma
sobre o salvamento.** O portão real é `validateAutomation`
(`app/javascript/dashboard/helper/validations.js`), chamado em
`AutomationRuleForm.vue:232-236` — só emite `save` se o objeto de erros vier vazio.

E a causa de um título em branco passar hoje é mais específica do que "falta validação":

```js
// validations.js, validateSingleAction
if (!noParamActions.includes(action.action_name) &&
    (!action.action_params || action.action_params.length === 0)) {
```

Para `create_pipeline_item_task` o `action_params` é um **objeto**
(`{ title, due_in_days }`), não um array. `{}.length` é `undefined` e `undefined === 0` é
`false`, então o guard genérico **nunca dispara** para essa ação — nem com o formulário
inteiro vazio.

### O que foi feito

| Arquivo | Mudança |
|---|---|
| `helper/validations.js` | Nova constante exportada `TASK_TITLE_REQUIRED` + checagem por nome do campo em `validateSingleAction`, com comentário explicando o furo do guard genérico. |
| `i18n/locale/en/automation.json` | `AUTOMATION.ERRORS.TASK_TITLE_REQUIRED` = "Task title is required". |
| `i18n/locale/pt_BR/automation.json` | Mesma chave = "O título da tarefa é obrigatório". `automation.json` é um dos três arquivos em que o `CLAUDE.md` manda manter `pt_BR` junto com `en` — não é desvio. |
| `services/concerns/pipeline_item_actions.rb` | `log_missing_task_title`, espelhando o `log_missing_task_assignee` que já existia. |

Nada foi alterado no componente nem no `rescue` genérico dos services (a task pede
explicitamente para não tocar no `rescue`). O erro já aparece na UI sozinho:
`AutomationActionInput.vue:253` renderiza `errorMessage` em vermelho com `animate-wiggle`, o
mesmo visual dos outros erros de ação — que é o "mesmo padrão visual" pedido. Esses inputs de
ação usam só placeholder, sem label, então não há padrão de asterisco a seguir.

### Título só com espaços também é bloqueado

A checagem usa `!action.action_params?.title?.trim()`, não só `!...title`. Motivo: o
`validates :title, presence: true` do Rails usa `blank?`, e `"   ".blank?` é `true` —
confirmado no console:

```
  "   ".blank? = true
  erro de title: ["can't be blank"]
```

Sem o `trim()`, um título de três espaços passaria no client e a falha silenciosa só mudaria de
lugar: sairia do formulário e voltaria em runtime, exatamente o bug que esta task corrige.

### Por que o log no backend, que a task não pedia

O fix do frontend impede **novas** automações quebradas, mas não repara as **já salvas** em
produção com título vazio. Essas continuam falhando dentro do `rescue StandardError` genérico
dos callers, e sem log nenhum ninguém descobre o motivo. Aprovado pelo usuário antes de
implementar.

### Verificação empírica

**Frontend** — spec temporário (`specs/tmp_task17_debug.spec.js`, apagado depois):

```
  title null ->          {"action_0":"TASK_TITLE_REQUIRED"}
  title empty string ->  {"action_0":"TASK_TITLE_REQUIRED"}
  no title key ->        {"action_0":"TASK_TITLE_REQUIRED"}
  title filled ->        {}
  other action ->        {}      <- create_pipeline_item (tambem objeto) nao foi afetado
  validateAutomation ->  {"action_0":"TASK_TITLE_REQUIRED"}
4 passed
```

**Com a checagem removida temporariamente**, os mesmos casos devolvem `{}` — ou seja, hoje a
automação com título vazio salva limpa, sem nenhum erro, que é exatamente a falha silenciosa
descrita:

```
  title null ->         {}
  validateAutomation -> {}
AssertionError: expected undefined to be 'TASK_TITLE_REQUIRED'
2 failed | 2 passed
```

Segundo spec temporário (`tmp_task17_trim.spec.js`, apagado depois) cobrindo o `trim()`:

```
  null           -> {"action_0":"TASK_TITLE_REQUIRED"}
  empty          -> {"action_0":"TASK_TITLE_REQUIRED"}
  three spaces   -> {"action_0":"TASK_TITLE_REQUIRED"}
  tab + newline  -> {"action_0":"TASK_TITLE_REQUIRED"}
  real title     -> {}
  padded title   -> {}      <- "  Ligar  " e aceito, so o vazio-em-branco e barrado
```

**Spec pré-existente** `helper/specs/validations.spec.js`: **5 de 5 passando** antes e depois —
nenhuma regressão nas validações de condição/ação já cobertas.

**Backend** — `rails runner` chamando o método do concern direto:

```
  titulo vazio: ActiveRecord::RecordInvalid: Validation failed: Title can't be blank
  tasks criadas: 0 (esperado 0)
  caminho feliz: task#58 title="Ligar para o cliente" due=2026-10-07
```

E o log saiu:

```
[PipelineItemActions] create_task_for_pipeline_item: blank title for pipeline_item#116408 -
task creation will fail validation (automation/macro saved before the title became required?)
```

**Lint:** `eslint` exit 0, `prettier --check` limpo nos 3 arquivos de frontend, `rubocop`
`1 file inspected, no offenses detected` no concern. Os dois `automation.json` foram
normalizados de CRLF para LF depois do `Edit` (o `HEAD` guarda LF) — **6ª ocorrência** do
problema de line-endings nesta base.
