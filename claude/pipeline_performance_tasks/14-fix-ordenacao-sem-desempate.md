# Task 14 — Fix: paginação sem desempate na ordenação repete e pula cards

Severidade: 🔴 Crítico. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

`app/finders/pipeline_item_finder.rb:89-100` ordena sem nenhum critério de desempate:

```ruby
def apply_sort(items)
  order = params[:order] == 'desc' ? 'desc' : 'asc'

  if params[:sort_by] == 'assignee'
    items.left_joins(:assignee).reorder(Arel.sql("COALESCE(users.name, '') #{order}"))
  else
    column = SORT_COLUMNS[params[:sort_by]] || SORT_COLUMNS['position']
    items.reorder(Arel.sql("#{column} #{order}"))
  end
end
```

SQL gerado (confirmado no container):

```sql
SELECT "pipeline_items".* FROM "pipeline_items"
WHERE "pipeline_items"."account_id" = 1 AND "pipeline_items"."pipeline_stage_id" = 8566
ORDER BY pipeline_items.position asc LIMIT 25 OFFSET 0
```

`LIMIT`/`OFFSET` sobre uma ordenação não-determinística **não tem garantia de particionar o
conjunto**: o Postgres pode devolver o mesmo card em duas páginas e nunca devolver outro. Não é
teórico — empates são a regra nesta tabela, não a exceção:

- `position` tem `default: 0` (`db/schema.rb:1085`) e nada atribui uma posição na criação, então
  **todo card criado pelo modal "Adicionar card", por automação ou por macro nasce com
  `position = 0`**.
- Confirmado no banco de dev: a stage 8566 tem 3 cards com a mesma `position`; a 8456 tem 2
  cards em `position = 0`.
- `created_at`/`updated_at` empatam em criação em lote (automação/macro/import); `value` empata
  no default `0.0`; `COALESCE(users.name, '')` empata em todo card sem responsável e em todo par
  de cards do mesmo agente.

O agravante: **isso não reproduz em desenvolvimento.** Com tabela pequena o Postgres faz seq
scan e devolve a mesma ordem física toda vez. Em produção, com índice em
`(pipeline_stage_id, position)` ou scan paralelo, a ordem entre linhas empatadas muda entre
execuções — e aí o agente vê card duplicado numa coluna e outro que sumiu.

## O que corrigir

Acrescentar `pipeline_items.id` como último critério em **todos** os ramos do `apply_sort` —
inclusive no ramo de `assignee`, e inclusive quando o `sort_by` é o default `position`. A
direção do desempate pode ser fixa (`asc`) ou acompanhar a direção principal; o que importa é
ser total e estável.

Referência do mesmo cuidado no projeto: `ConversationFinder::SORT_OPTIONS`
(`app/finders/conversation_finder.rb:5-23`) resolve para scopes do model
(`sort_on_last_activity_at` etc.) — conferir se esses scopes já desempatam por `id` e, se sim,
seguir a mesma forma aqui em vez de inventar.

## Testes

1. `EXPLAIN` da query gerada antes e depois — confirmar que o `ORDER BY` passou a ter o
   segundo critério.
2. Reprodução direta do bug, com `PIPELINE_ITEMS_RESULTS_PER_PAGE=1` no container e uma stage
   com 3+ cards na mesma `position`: pedir página 1, 2 e 3 e conferir que os ids são disjuntos
   e cobrem o conjunto. Rodar várias vezes — o ponto é a estabilidade entre execuções, não um
   acerto isolado.
3. Repetir para cada `sort_by` (`position`, `created_at`, `updated_at`, `value`, `assignee`),
   asc e desc, garantindo empates em cada um (vários cards sem responsável para o `assignee`).
4. Pelo board: rolar uma coluna grande até o fim e conferir que nenhum card aparece duas vezes
   e que o total carregado bate com o badge.

## Critério de pronto

- Todo `ORDER BY` emitido pelo finder termina num critério único (`pipeline_items.id`).
- Páginas consecutivas de uma mesma coluna são disjuntas e completas, de forma repetível, com
  empates em qualquer um dos 5 campos de ordenação.
- `bundle exec rubocop -a` limpo.

## Observação relacionada (não faz parte desta task)

A causa de fundo do empate em `position` é que nada atribui uma posição na criação do card.
Corrigir o desempate resolve a paginação de forma definitiva e é o suficiente; atribuir
`position` incremental na criação seria uma mudança de comportamento à parte — avaliar
separadamente, não misturar aqui.

## Resultado (registrado em 2026-09-21, implementado e verificado na auditoria de 2026-09-18)

`PipelineItemFinder#apply_sort` (`app/finders/pipeline_item_finder.rb`) acrescenta
`pipeline_items.id` como último critério de `ORDER BY` nos dois ramos, na **mesma direção** do
critério principal: coluna simples (`position`, `created_at`, `updated_at`, `value`) e `assignee`
(`COALESCE(users.name, '') <dir>, pipeline_items.id <dir>`). SQL emitido para o padrão:
`ORDER BY pipeline_items.position asc, pipeline_items.id asc`.

Reverificado em 2026-09-21 no finder real (6 cards na mesma stage com `position`, `created_at` e
`updated_at` empatados, `value` com repetidos e um `NULL`, páginas de 1 item, 5 campos × asc/desc =
10 combinações): em **todas** as 10 as páginas voltaram disjuntas e completas, e o resultado com
empate é determinístico (id como desempate, invertido em `desc`). Dados de teste removidos.

A "Observação relacionada" (nada atribuía `position` na criação) virou a
[task 24](24-fix-reorder-posicoes-cards-nao-carregados.md), já feita: o card agora nasce com
`position` no fim da stage (`PipelineStage#next_position`).
