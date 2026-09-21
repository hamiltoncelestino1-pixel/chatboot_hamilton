# Task 20 — Fix: filtro de valor exclui cards com `value` NULL

Severidade: 🟡 Média. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

`app/finders/pipeline_item_finder.rb:70-76`:

```ruby
def filter_by_value_range(items)
  return items if params[:value_min].blank? && params[:value_max].blank?

  min = params[:value_min].presence&.to_f
  max = params[:value_max].presence&.to_f
  items.where(pipeline_items: { value: min..max })
end
```

`WHERE value BETWEEN min AND max` **exclui `NULL`** — em SQL, `NULL BETWEEN 0 AND 100` é `NULL`,
não `true`. O cliente faz o contrário (`getters.js:52-56`, e idem no código anterior):

```js
const v = Number(item.value) || 0;
if (valueRange.min != null && v < valueRange.min) return false;
if (valueRange.max != null && v > valueRange.max) return false;
```

`Number(null) || 0` → `0`, ou seja, **card sem valor conta como 0** e entra na faixa sempre que
`min <= 0 <= max`.

A coluna é nullable (`db/schema.rb:1083`, `default: "0.0"` mas sem `null: false`), e no banco de
dev já existe 1 card em 21 com `value` nulo — então é um caso real, não hipotético. Um agente que
filtra "valor de 0 a 1000" para achar as oportunidades pequenas deixa de ver os cards sem valor
preenchido, que são exatamente os que ele provavelmente quer achar.

O mesmo desencontro faz o servidor e o `itemMatchesActiveFilters` (usado pelos pushes de
ActionCable) discordarem: um card sem valor não vem na listagem, mas se for atualizado durante a
sessão o predicado do cliente diz que ele casa com o filtro.

## O que corrigir

1. Decidir a semântica (é decisão de produto, mas com um padrão óbvio):
   - **Tratar NULL como 0 (recomendado)** — alinha ao comportamento que está em produção e ao
     predicado do cliente. Em SQL: envolver a coluna em `COALESCE(pipeline_items.value, 0)` na
     comparação, ou acrescentar um `OR value IS NULL` quando a faixa inclui o zero.
   - **Excluir NULL** — mantém o servidor como está, e aí `itemMatchesActiveFilters` precisa ser
     alinhado para também excluir (`item.value == null → false`).
2. Aplicar nos dois lados (finder + `getters.js:52-56`), como na task 17 — o problema não é o
   valor escolhido, é os dois lados discordarem.
3. Conferir de passagem se `COALESCE` na cláusula `WHERE` estraga o uso de índice. Hoje não há
   índice em `value` (`db/schema.rb:1095-1105`), então não estraga nada — só não criar um depois
   sem lembrar disso.

## Testes

1. Garantir no banco de dev pelo menos um card com `value` NULL, um com `0`, e alguns com
   valores variados na mesma coluna.
2. Filtrar `min = 0`: o card NULL aparece (ou não) conforme a decisão — e o mesmo resultado tem
   que sair pelos dois caminhos: a listagem do servidor e o `itemMatchesActiveFilters` quando
   aquele card é atualizado em outra sessão.
3. Filtrar `min = 10`: o card NULL **não** deve aparecer em nenhuma das duas semânticas (0 < 10).
4. Filtrar só `max`, só `min`, e os dois — as três combinações passam por ramos diferentes do
   range Ruby (`nil..max`, `min..nil`, `min..max`).
5. Conferir que `meta.count` bate com o número de cards listados em cada caso.

## Critério de pronto

- Servidor e `itemMatchesActiveFilters` concordam sobre o que fazer com `value` NULL.
- Decisão registrada neste arquivo.
- `bundle exec rubocop -a` e `pnpm eslint` limpos.

## Decisão e resultado (2026-09-17)

**Tratar NULL como 0**, a opção recomendada — mesma lógica da task 17: alinha o servidor ao que
já está em produção no cliente.

Igual à 17, só **um** lado estava errado. `itemMatchesActiveFilters` (`getters.js:52-56`) já faz
`Number(item.value) || 0` — trata NULL como 0 desde sempre. O bug estava isolado em
`PipelineItemFinder#filter_by_value_range`, que usava `where(value: min..max)` (Range do Ruby →
`BETWEEN`, que exclui NULL em SQL). Nenhuma mudança em `getters.js` foi necessária.

Fix: trocado o range hash por duas condições `COALESCE(pipeline_items.value, 0) >= ?` /
`<= ?`, aplicadas só quando o respectivo `min`/`max` está presente (preserva os 3 ramos:
só min, só max, os dois). Sem índice em `value` hoje, então `COALESCE` no `WHERE` não estraga
nada (e o comentário deixa isso registrado para quem for indexar essa coluna no futuro).

Verificado no Docker local com 5 cards (`NULL`, `0`, `5`, `50`, `500`) nas 5 combinações do plano
de teste — todas bateram exatamente com o esperado, incluindo os casos de borda (`min=0` traz
tudo; `min=10` exclui NULL/0/5; `min=1` exclui só NULL/0) — e `meta_count` consistente com a
listagem em cada uma.

`bundle exec rubocop -a`: limpo. `bundle exec rspec` (pipeline_items_controller): 6/6 passando.
