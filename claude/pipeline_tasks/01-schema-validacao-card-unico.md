# Task 01 — Schema: coluna `pipeline_id` + validação de unicidade em `PipelineItem`

Parte do Grupo A ([visão geral](00-visao-geral.md)). Sem dependências — pode começar primeiro.

## Objetivo

Hoje `pipeline_items` não tem coluna `pipeline_id` — o pipeline só é alcançado via
`pipeline_stage_id → pipeline_stages.pipeline_id` (`delegate :pipeline, to: :pipeline_stage`
em `app/models/pipeline_item.rb`). Sem essa coluna direta, não dá para ter um índice único
simples `(pipeline_id, contact_id)`. Esta task cria a coluna, o backfill e a validação —
mas a constraint definitiva (NOT NULL + índice único) só entra depois da task 02 (mesclagem
dos dados existentes), para não quebrar o `db:migrate` com dados já duplicados.

## 1. Migration: adicionar coluna `pipeline_id`

Novo arquivo `db/migrate/<timestamp>_add_pipeline_id_to_pipeline_items.rb`. Seguir o estilo
já usado em `db/migrate/20260701100004_add_assignee_and_team_to_pipeline_items.rb` (ler esse
arquivo antes, para reaproveitar exatamente o idiom de `add_reference`/`add_foreign_key`
usado nesta tabela). Coluna **nullable** por enquanto:

```ruby
add_reference :pipeline_items, :pipeline, foreign_key: true, index: true
```

## 2. Migration: backfill

Novo arquivo `db/migrate/<timestamp>_backfill_pipeline_id_on_pipeline_items.rb` — migration de
dados (sem alterar schema), preenche a partir do stage já existente:

```sql
UPDATE pipeline_items
SET pipeline_id = pipeline_stages.pipeline_id
FROM pipeline_stages
WHERE pipeline_stages.id = pipeline_items.pipeline_stage_id
  AND pipeline_items.pipeline_id IS NULL
```

(ou equivalente em batches via ActiveRecord, se o volume de dados justificar evitar um único
`UPDATE` grande). Idempotente — pode rodar de novo sem efeito colateral.

## 3. Model — sincronizar `pipeline_id` automaticamente

Em `app/models/pipeline_item.rb`:

- Adicionar `belongs_to :pipeline, optional: true` — associação nova, só para uso interno
  (consulta/índice). **Não remover** `delegate :pipeline, to: :pipeline_stage` — é o caminho
  público de leitura já usado em toda a base (controllers, serializers, views), e não deve
  mudar de comportamento.
- Adicionar callback `before_validation :set_pipeline_id_from_stage`, que sincroniza
  `pipeline_id = pipeline_stage.pipeline_id` sempre que `pipeline_stage_id` estiver presente
  e tiver mudado (ou no create). Isso garante que **nenhum chamador precise passar
  `pipeline_id` manualmente** — nem o controller, nem os novos serviços de automação/macro
  (tasks 04/06), nem o `Pipelines::ExportItemService` existente.
- Adicionar validação nova:
  ```ruby
  validates :contact_id, uniqueness: {
    scope: :pipeline_id,
    message: -> (object, data) { I18n.t('errors.pipeline_item.duplicate_contact_in_pipeline') }
  }
  ```
  Mirror exato do padrão já usado em `app/models/pipeline_member.rb`
  (`validates :user_id, uniqueness: { scope: :pipeline_id }`).

**Atenção**: como a validação de unicidade entra em produção nesta task mas o índice único
do banco só entra na task 02 (depois da mesclagem), esta validação Rails-only já bloqueia
criação de NOVOS duplicados via `save!`/`valid?` a partir de agora — o que é desejável (o
cliente confirmou "bloquear com erro" para novas tentativas). O que falta até a task 02 é
apenas a proteção contra condição de corrida (dois requests simultâneos passando pela
validação Rails ao mesmo tempo) — aceitável como risco residual transitório, documentado no
risco #1 da visão geral, resolvido definitivamente quando o índice único entrar.

## 4. i18n

`config/locales/en.yml` e `config/locales/pt_BR.yml` — nova chave, seguindo o padrão já usado
para outros erros de `pipeline_item` (`errors.pipeline_item.*`):

```yaml
errors:
  pipeline_item:
    duplicate_contact_in_pipeline: "This contact already has a card in this pipeline."
```
(pt_BR: "Este contato já possui um card neste pipeline.")

## 5. Não expor `pipeline_id` na API

Verificar `app/views/api/v1/accounts/models/_pipeline_item.json.jbuilder` (ou serializer
equivalente) — **não adicionar** `pipeline_id` na resposta JSON. Manter `pipeline` (via
`pipeline_stage.pipeline`) como a única representação pública, para não criar dependência de
clientes externos num detalhe interno de denormalização que pode mudar depois.

## Testes

Novo arquivo `spec/models/pipeline_item_spec.rb` — **hoje não existe nenhum spec de model
para PipelineItem**, então esta task também cobre as validações já existentes que nunca
tiveram teste, além da nova:

- Presença de `contact_id`/`pipeline_stage_id` (já existentes).
- `assignee_must_be_pipeline_member` (já existente, sem teste hoje).
- `labels_must_be_pipeline_type` (já existente, sem teste hoje).
- `conversation_must_belong_to_contact` (já existente, sem teste hoje).
- **Novo**: criar 2 cards do mesmo contato, mesmo pipeline, estágios diferentes → segundo é
  inválido com a mensagem correta.
- **Novo**: criar 2 cards do mesmo contato, pipelines diferentes → ambos válidos.
- **Novo**: `pipeline_id` sincroniza corretamente ao criar e ao trocar `pipeline_stage_id`
  (mover para stage de outro pipeline via `update!`).

## Critério de pronto

- Migrations rodam limpo em uma base local com dados de seed padrão (`bundle exec rails
  db:seed`).
- `spec/models/pipeline_item_spec.rb` passa.
- `bundle exec rubocop -a` sem novos warnings nos arquivos tocados.
