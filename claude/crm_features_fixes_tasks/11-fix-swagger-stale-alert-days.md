# Task 11 — Fix: `stale_alert_days` ausente do Swagger

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/models/pipeline.rb:11` define o campo, `app/controllers/api/v1/accounts/pipelines_controller.rb:32-34`
aceita no `pipeline_params`, `app/views/api/v1/models/_pipeline.json.jbuilder:10` retorna na
resposta. Confirmado por busca em todo `swagger/`: `stale_alert_days` não aparece em nenhum
arquivo — nem em `swagger/definitions/resource/pipeline.yml` nem em
`swagger/definitions/request/pipeline/create_update_payload.yml`. O commit `df0251e58` (que
introduziu o campo) não tocou nenhum dos dois YAMLs.

## O que corrigir

Adicionar `stale_alert_days` (integer, nullable) a:
- `swagger/definitions/resource/pipeline.yml` (campo de resposta)
- `swagger/definitions/request/pipeline/create_update_payload.yml` (campo aceito em
  create/update)

Rodar `bundle exec rails swagger:build` depois de editar os YAMLs (regra de memória do
projeto: nova tag/campo exige esse passo pra aparecer corretamente no Swagger UI e nas specs
validadas por Skooma).

## Testes

Confirmar visualmente no Swagger UI que `stale_alert_days` aparece no schema de `Pipeline` e
no payload de create/update de Pipeline. Se houver specs de request pra `PipelinesController`,
rodar (`bundle exec rspec spec/requests/api/v1/accounts/pipelines_controller_spec.rb`, se
existir) pra confirmar que o Skooma não acusa divergência.

## Critério de pronto

- `stale_alert_days` documentado no Swagger, coerente com o que a API de fato aceita/retorna.
- `bundle exec rails swagger:build` rodado sem erro.

## Decisão e resultado (2026-09-30)

**Escopo ampliado, com aprovação do usuário: 4 campos, não 1.** Ao abrir os dois YAMLs, o
`stale_alert_days` não era a única lacuna — `enable_auto_assignment`, `max_assignment_limit` e
`sync_assignments` também estão na resposta (`_pipeline.json.jbuilder:7-10`) e no
`pipeline_params` (`pipelines_controller.rb:41-43`) sem aparecer no Swagger. Mesma classe de bug
(o commit que adicionou cada campo não tocou os YAMLs), mesmos dois arquivos. O próprio critério
de pronto pede coerência com o que a API aceita/retorna, então deixar três lacunas conhecidas
para trás contrariaria a task.

Tipos usados, seguindo o estilo já presente nos arquivos (`type: number` para inteiros,
lista com `'null'` para anuláveis):

| Campo | Coluna | Swagger |
|---|---|---|
| `enable_auto_assignment` | boolean, not null, default false | `boolean` |
| `max_assignment_limit` | integer, not null, default 0 | `number` |
| `sync_assignments` | boolean, not null, default false | `boolean` |
| `stale_alert_days` | integer, **nullable** | `[number, 'null']` |

Os quatro são opcionais no payload de create/update (`required` segue só com `name`).

**Decisão deliberada: sem `minimum: 0`**, apesar de `max_assignment_limit` e `stale_alert_days`
terem `numericality: { greater_than_or_equal_to: 0 }` no model. Razão concreta: o Skooma valida
requests reais contra o schema, e um spec futuro que envie `-1` de propósito para testar o 422
passaria a ser acusado como request não-conforme. O ganho de documentação não paga esse risco.

### Verificação

`bundle exec rails swagger:build` no container: **"Swagger build was successful"**, sem erro.

O build alterou 7 arquivos, **218 inserções e nenhuma remoção** — conferido que toda linha
alterada nos 4 `swagger/tag_groups/*.json` é explicada pelos 4 campos novos (eles embutem os
component schemas compartilhados), sem nenhum ruído de regeneração.

JSON gerado conferido programaticamente (OpenAPI 3.1.0, parse OK):

```
resource.stale_alert_days  ["number","null"]
payload. stale_alert_days  ["number","null"]
payload required:          ["name"]
```
(os outros três saíram como `boolean`/`number` nos dois schemas)

**Paridade com a resposta real**, que é o critério que importa: renderizei
`api/v1/models/_pipeline` com um `Pipeline` real via `ApplicationController.render` e comparei as
chaves com as propriedades do schema:

```
campos na resposta real: 12
campos documentados:     12
na resposta mas NAO documentados: nenhum
documentados mas NAO na resposta: nenhum
```

**Nota sobre Skooma:** não existem request specs de `PipelinesController` (só
`spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb`, que é controller spec e não
`:request`). Então nenhum spec valida este schema automaticamente — a paridade medida acima é a
evidência que substitui isso.
