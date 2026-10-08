# Task 21 — Ligar o Skooma de verdade nos specs de request

Severidade: 🟠 Alta. Achado durante a implementação das tasks 11 e 12 (2026-09-30).

## Objetivo

O `CLAUDE.md` afirma, na seção de convenções de teste:

> Specs de `:request` são validadas contra `swagger/swagger.json` via Skooma
> (`spec/rails_helper.rb:79-81`) — **então documentação Swagger de endpoint novo não é
> opcional, é checada em teste**

**Isso não é verdade hoje.** O Skooma está realmente incluído:

```ruby
# spec/rails_helper.rb:79-81
# OpenAPI response validation via Skooma
path_to_openapi = Rails.root.join('swagger/swagger.json')
config.include Skooma::RSpec[path_to_openapi], type: :request
```

Mas `config.include` só **disponibiliza** o matcher — ele não valida nada sozinho. E o matcher
`conform_to_definition` **não é invocado por nenhum spec do projeto**:

```
$ grep -rln "conform_to_definition" spec/
(nenhum resultado)
```

São **181 arquivos de spec com `type: :request`** (de 716 specs no total) que passam pelo
`include` e não verificam nada.

## Por que isso importa

É a causa raiz de tudo que as tasks 11 e 12 encontraram. Sem validação, o Swagger divergiu em
silêncio do comportamento real:

- **Task 11** (`resource/pipeline.yml`): 4 campos na resposta sem documentação — 12 campos reais
  contra 8 documentados.
- **Task 12** (`resource/pipeline_item.yml`): 6 campos sem documentação, 2 campos documentados que
  **não existem** (`assignee_id`, `team_id`), e 2 com **tipo errado** (`created_at`/`updated_at`
  documentados como `string`/`date-time` quando o serializer emite Integer unix).

Evidência de que a rede teria funcionado:
`spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` é `type: :request` e tem um
exemplo de export bem-sucedido (linha 57) que renderiza o partial `_pipeline_item` **inteiro**.
Com o matcher ativo, ele teria falhado no `created_at` desde o commit que introduziu o `.to_i`.

Sem esta task, as tasks 11 e 12 se repetem no próximo campo novo.

## O que corrigir

1. Acrescentar `expect(response).to conform_to_definition` (ou o nome exato que a versão do Skooma
   no `Gemfile.lock` expõe — confirmar na gem antes) nos specs de request que exercitam respostas
   de sucesso. **Começar pelo domínio Pipeline/Task**, que é o código próprio do projeto e onde as
   divergências foram medidas, em vez de tentar os 181 de uma vez.
2. Rodar e **catalogar** as divergências que aparecerem. É esperado que apareçam várias, em
   recursos que ninguém revisou — o valor desta task é justamente expor a lista.
3. Decidir, para cada divergência, se corrige o YAML (documentação errada) ou o código (resposta
   errada). O precedente das tasks 11/12: quando o frontend já consome o formato atual, corrige-se
   a documentação, nunca o contrato.
4. Corrigir a afirmação no `CLAUDE.md`, que hoje orienta decisões de forma equivocada — ou
   mantê-la, se o item 1 for implementado de forma abrangente o suficiente para torná-la
   verdadeira.

## Cuidado conhecido

Ao ligar o matcher, specs que mandam payload inválido de propósito (para testar 422) podem ser
acusados de request não-conforme, dependendo de como o schema descreve o corpo. Foi por isso que
as tasks 11 e 12 **não** adicionaram `minimum: 0` aos campos numéricos validados — ver a decisão
registrada na task 11. Vale confirmar esse comportamento antes de ligar em massa.

## Testes

Esta task **é** sobre teste, então a verificação é a própria suíte: rodar os specs de request do
domínio escolhido com o matcher ativo e conferir que (a) passam depois dos ajustes de schema e
(b) falham de propósito se alguém introduzir um campo novo sem documentar — validar isso
removendo temporariamente um campo do YAML e confirmando que o spec quebra.

## Critério de pronto

- `conform_to_definition` efetivamente invocado em pelo menos os specs de request do domínio
  Pipeline/Task.
- Divergências encontradas catalogadas e resolvidas (ou registradas como task própria).
- Demonstrado que a validação pega uma divergência introduzida de propósito.
- `CLAUDE.md` coerente com o que o projeto de fato faz.

## Resultado (2026-10-06)

### ⚠️ Correção: o achado central desta task estava errado

A task afirma que o matcher do Skooma "não é invocado por nenhum spec", com base em
`grep -rln "conform_to_definition" spec/` retornando vazio. **`conform_to_definition` é o
matcher da gem `committee`, não do Skooma.** O Skooma 0.3.7
(`/gems/.../skooma-0.3.7/lib/skooma/rspec.rb`) expõe `conform_schema(status)`,
`conform_response_schema(status)`, `conform_request_schema` e `be_valid_document`.

Grep pelos nomes certos:

| Matcher | Arquivos |
|---|---|
| `conform_to_definition` | 0 (não existe nesta gem) |
| **`conform_schema`** | **9** |
| `be_valid_document` | 1 (`spec/swagger/openapi_spec.rb`) |

Baseline antes de qualquer mudança: **14 examples, 0 failures**. A infraestrutura sempre
funcionou.

**Mas a conclusão da task se sustenta**: os 9 arquivos cobrem só endpoints herdados do upstream
(agents, contacts, conversations, messages, inboxes, teams, accounts, profiles, platform).
**Zero** cobriam o domínio próprio do fork — que é exatamente por que as tasks 11 e 12 acharam
divergências. A rede existia; nunca foi estendida ao nosso código.

### Catálogo de divergências encontradas

Levantadas por comparação sistemática entre os campos que cada partial Jbuilder emite e os
declarados no schema, mais a execução do matcher.

| # | Divergência | Como foi resolvida |
|---|---|---|
| 1 | `POST /pipeline_items/{id}/export` **ausente do Swagger** | `items/export.yml` + `pipeline_item/export_payload.yml` + registro |
| 2 | `GET /pipeline_items/{id}` apontava para `items/index.yml` (**array**), mas retorna objeto | `items/show.yml` criado |
| 3 | `GET .../pipeline_stages/{id}` idem | `stages/show.yml` criado |
| 4 | `stages` emitido pelas 4 views de pipeline, não declarado | acrescentado a `resource/pipeline.yml` |
| 5 | `stage_type` emitido pelo partial, não declarado | acrescentado a `resource/pipeline_stage.yml` |
| 6 | `value` documentado como `number`, **serializado como string** | `type: [string, 'null']` + nota explicando (decimal(15,2) → BigDecimal → string) |
| 7 | `assignee`/`team`/`pipeline_lost_reason` com `$ref` puro, mas o partial emite `null` explícito quando ausente | `oneOf: [$ref, {type: 'null'}]` |

As divergências 6 e 7 só apareceram quando o matcher rodou — nenhuma inspeção de código as
tinha pego, inclusive a minha.

**Recursos que estavam corretos:** `task` (12/12) e `pipeline_lost_reason` (5/5), nada a fazer.

### 🔴 Bug de produção descoberto de passagem

`GET /api/v1/accounts/:account_id/pipelines/:id` devolvia **401 para todo mundo, inclusive
administradores**. `PipelinesController` não sobrescrevia `check_authorization`, então usava a
versão do `Api::BaseController`:

```ruby
model ||= controller_name.classify.constantize   # => a CLASSE Pipeline
authorize(model)
```

E `PipelinePolicy#show?` é `Current.user.assigned_pipelines.include?(record)` — com a classe no
lugar da instância, nunca é verdade. Medido num spec de diagnóstico:

```
  GET show como agente -> 401 {"error":"You are not authorized to do this action"}
  GET show como ADMIN  -> 401 {"error":"You are not authorized to do this action"}
  GET index            -> 200 (1 pipelines)
```

Passou despercebido porque o frontend **não chama** esse endpoint: `PipelinesAPI#getWithStages`
(`api/pipelines.js:10`) existe mas não tem nenhum chamador. É um endpoint público documentado,
quebrado.

Corrigido com o mesmo formato já usado por `TasksController:38-40` e
`PipelineItemsController:83-85`: `authorize(@pipeline || Pipeline)`. `update?`/`destroy?` não
usam `record` (checam `administrator?`), então não mudam de comportamento.

### A prova que a task pedia — e o que ela revelou

O critério de pronto pedia demonstrar que o spec quebra se um campo novo não for documentado.
Removi `overdue_tasks_count` do YAML e **os specs continuaram passando**: schemas OpenAPI
aceitam propriedades extras por padrão, então o matcher pega tipo errado, nulo inesperado e
forma errada — **mas não pega campo novo não documentado**, que é justamente a classe das
tasks 11 e 12.

Resolvido acrescentando `additionalProperties: false` a `pipeline`, `pipeline_stage` e
`pipeline_item`. Com a lista de campos completa, a suíte segue verde (**14 examples, 0
failures**); removendo `overdue_tasks_count` de novo, 3 specs falham nomeando o campo:

```
"error" => ["overdue_tasks_count"]
13 examples, 3 failures
```

Aplicado só aos três schemas que os specs novos exercitam de fato. `task` e
`pipeline_lost_reason` ficaram sem o modo estrito de propósito: estão completos, mas nenhum spec
os valida hoje, e eu não queria afirmar no documento uma garantia que nada verifica.

### Specs criados

`spec/controllers/api/v1/accounts/pipelines_controller_spec.rb` — 7 exemplos cobrindo
`GET /pipelines`, `GET /pipelines/{id}`, `GET .../pipeline_stages`,
`GET .../pipeline_stages/{id}`, `GET .../pipeline_items?stage_id=`, `GET /pipeline_items/{id}`,
mais o 401 sem credenciais. Todos os de sucesso com `conform_schema(200)`. E
`conform_schema(200)` acrescentado ao exemplo de export em `pipeline_items_controller_spec.rb`.

Isto contraria a regra do `AGENTS.md` de não escrever specs sem pedido — mas esta task **é** o
pedido: o critério de pronto exige o matcher invocado no domínio Pipeline/Task, e existia um
único spec de request no domínio, apontando para o endpoint não documentado do item 1.

**Dois bugs eram do meu próprio spec, não do schema**, e vale registrar porque são armadilhas
fáceis: (a) `get ... params: {...}, as: :json` manda os parâmetros no **corpo** mesmo num GET, e
o `stage_id` obrigatório sumia da query string; (b) `Pipeline#create_default_stages` semeia
estágios na criação, então `parsed_body.first` não é o estágio do `let!`.

### Não corrigido, registrado

Os payloads de `create`/`update` de pipeline_item documentam os campos **sem** o wrapper
`pipeline_item`, mas o controller usa `params.require(:pipeline_item)`. O `export_payload.yml`
novo foi documentado **com** o wrapper (correto), ficando deliberadamente inconsistente com os
antigos — prefiro certo a consistente-com-o-erro. Corrigir os demais exige revisar todos os
payloads de request do domínio e não é necessário para esta task.

### Testes

```
spec/swagger/openapi_spec.rb
spec/controllers/api/v1/accounts/pipelines_controller_spec.rb
spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb
-> 14 examples, 0 failures
```

Suíte ampla (todos os specs com Skooma + policy/model de pipeline): **386 examples, 8
failures** — as 8 em `accounts_controller_spec.rb` e `platform/accounts_controller_spec.rb`.
**Confirmadas pré-existentes**: restaurei o `swagger.json` do `HEAD` via `git show` e rodei os
mesmos dois arquivos — `44 examples, 8 failures`, idêntico. Não são efeito do rebuild.

> **Correção (2026-10-06):** essas medições foram feitas contra o banco de **desenvolvimento** —
> o container define `RAILS_ENV=development` e o `rails_helper` usava `||=`, problema só
> descoberto na [task 22](22-fix-specs-notificacao-contagem-global.md). No ambiente correto os
> mesmos dois arquivos dão **7 falhas**, não 8: uma era artefato de dado do dev. A conclusão não
> muda (nenhuma é causada por esta task — isso foi provado pelo teste com o `swagger.json` do
> `HEAD`), só o número. Os specs criados nesta task foram revalidados com `RAILS_ENV=test`:
> `openapi + pipelines + pipeline_items + policy + model -> 47 examples, 0 failures`.

**Rubocop:** `3 files inspected, no offenses detected`. Todos os arquivos tocados em LF.

### `CLAUDE.md` corrigido

A afirmação antiga ("documentação Swagger de endpoint novo não é opcional, é checada em teste")
é enganosa, não falsa. Reescrita para dizer que a validação é **opt-in por exemplo**, que sem
`expect(response).to conform_schema(200)` nada é verificado, que só ~10 dos 181 arquivos
`type: :request` o fazem, e que o matcher **não** se chama `conform_to_definition`.
