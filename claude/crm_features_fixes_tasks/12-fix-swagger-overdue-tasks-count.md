# Task 12 — Fix: `overdue_tasks_count` ausente do Swagger

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).
Depende da task 04 (o campo precisa estar correto em todas as actions antes de documentar).

## Objetivo

`app/views/api/v1/models/_pipeline_item.json.jbuilder:38` retorna `overdue_tasks_count` — é o
próprio dado que entrega a feature de badge de tarefa vencida do commit `df0251e58`. Confirmado
por busca em todo `swagger/`: `overdue_tasks_count` não aparece em nenhum arquivo, incluindo
`swagger/definitions/resource/pipeline_item.yml` (que o commit editou pra adicionar
`pipeline_lost_reason_id`/`pipeline_lost_reason`, mas não esse campo).

## O que corrigir

Adicionar `overdue_tasks_count` (integer) a `swagger/definitions/resource/pipeline_item.yml`.
Rodar `bundle exec rails swagger:build` depois.

## Testes

Confirmar visualmente no Swagger UI que `overdue_tasks_count` aparece no schema de
`PipelineItem`.

## Critério de pronto

- `overdue_tasks_count` documentado no Swagger.
- `bundle exec rails swagger:build` rodado sem erro.

## Decisão e resultado (2026-09-30)

**Escopo ampliado com aprovação do usuário.** A medição de paridade (mesmo método da task 11)
mostrou que `overdue_tasks_count` era uma de **quatro** classes de divergência no
`swagger/definitions/resource/pipeline_item.yml` — resposta real com 20 campos contra 16
documentados, e nem todas as divergências eram omissão:

| Problema | Campos | Ação |
|---|---|---|
| Na resposta, não documentados | `overdue_tasks_count` (a task), `pipeline_id`, `pipeline_name`, `pipeline_stage_name`, `label_list`, `custom_attributes` | adicionados |
| Documentados mas inexistentes | `assignee_id`, `team_id` | **removidos** — conferido que nenhuma view de pipeline_item os emite |
| **Tipo errado** | `created_at`, `updated_at` | corrigidos para `number` |

O tipo errado era o mais grave: documentados como `string`/`format: date-time`, mas o serializer
faz `.to_i` (`_pipeline_item.json.jbuilder:12-13`) e emite **Integer unix** — medido `1783958368`.
Um cliente gerado a partir do schema tentaria parsear inteiro como ISO-8601.

**Decisão: corrigir a documentação, não o código.** Mudar o jbuilder para emitir ISO-8601 seria
quebrar o contrato com o frontend, que já consome inteiro. A descrição dos dois campos diz
explicitamente que é timestamp Unix e não ISO, para ninguém "consertar" isso por engano depois.
Nota: `_pipeline.json.jbuilder` **não** usa `.to_i`, então `resource/pipeline.yml` está correto
com `string`/`date-time` — a inconsistência é entre os dois recursos da API, e é pré-existente.

### ⚠️ Achado que contradiz o `CLAUDE.md`

O `CLAUDE.md` afirma que specs de request são validadas contra `swagger/swagger.json` via Skooma,
e que por isso "documentação Swagger de endpoint novo não é opcional, é checada em teste".
**Não é o caso hoje.** O Skooma está incluído em `spec/rails_helper.rb:81`
(`config.include Skooma::RSpec[path_to_openapi], type: :request`), mas o matcher
`conform_to_definition` **não é invocado por nenhum spec do projeto** — `grep -rln
"conform_to_definition" spec/` não retorna nada.

Consequência: o Swagger não tem rede de teste nenhuma, o que explica como estas divergências
acumularam em silêncio. `spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` é
`type: :request` e exercita um export bem-sucedido que renderiza o partial inteiro — teria pegado
o tipo errado de `created_at` se o matcher fosse usado. Vale virar task própria (adicionar
`expect(response).to conform_to_definition` nos specs de request existentes).

### Verificação

`bundle exec rails swagger:build`: **"Swagger build was successful"**.

Paridade medida depois da correção, com o partial renderizado a partir de um `PipelineItem` real:

```
resposta real: 20 | documentados: 20
na resposta mas NAO documentados: nenhum
documentados mas ausentes da resposta: nenhum

created_at -> "number"   (resposta: Integer)
updated_at -> "number"
label_list -> "array" items "string"
overdue_tasks_count -> "number"
```

`rspec spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb`: **6 examples,
0 failures** (sem mudança — o spec não aciona o Skooma, ver achado acima).
