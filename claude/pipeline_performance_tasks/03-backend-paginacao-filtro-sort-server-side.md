# Task 03 — Backend: paginar, filtrar e ordenar o board no servidor

Severidade: 🟠 Alta. Achado na análise de performance de 2026-09-15.
Depende da task 02 (os `includes` corretos precisam existir antes de paginar, senão a medição
de ganho fica confusa).

## Objetivo

`app/controllers/api/v1/accounts/pipeline_items_controller.rb:80-86` devolve **todos** os cards
do pipeline, sem `page` nem `limit`:

```ruby
def nested_pipeline_index
  @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
  @items = pipeline_items_scope
  @items = @items.where(pipeline_stage_id: params[:stage_id]) if params[:stage_id].present?
  @overdue_tasks_counts = overdue_tasks_counts_for(@items)
  render :index
end
```

Filtro e ordenação só existem no cliente (`store/modules/kanban/getters.js:59-99`), o que só
funciona porque o cliente tem tudo. **Paginar sem mover filtro/sort para o servidor daria
resultado errado** — o agente filtraria apenas a página carregada e acharia que não há mais
resultados.

Decisão de produto já tomada: a ordem padrão da coluna passa a ser `position` (ordem manual de
arrasto). Isso corrige de quebra um bug real: hoje `getFilteredSortedItemsForStage` sempre
reordena por `created_at desc` (default em `constants.js:9-12`), então arrastar um card dentro
da coluna persiste `position` no banco mas o `watch(storeItems)` de `KanbanColumn.vue:28-30`
devolve o card pro lugar. **Arrastar para reordenar está quebrado em produção hoje.**

## O que corrigir

### 1. Paginação

Em `nested_pipeline_index`, Kaminari `.page(...).per(...)` seguindo o padrão de
`contacts_controller.rb:12,129,133-142`, com per-page configurável por ENV no mesmo formato de
`conversation_finder.rb:215`:

```ruby
RESULTS_PER_PAGE = ENV.fetch('PIPELINE_ITEMS_RESULTS_PER_PAGE', '25').to_i
```

`stage_id` passa a ser **obrigatório** neste caminho (o board pede uma coluna por vez).
Retornar 400 se ausente, ou manter o comportamento atual sem paginar — decidir na
implementação, mas documentar a escolha no Swagger (task 04).

`overdue_tasks_counts_for(@items)` (`:88-93`) faz `items.map(&:id)`, o que materializa a
relação. Precisa ser chamado **depois** do `.page().per()`, senão continua carregando tudo.

### 2. Envelope de resposta

View nova (ex. `app/views/api/v1/accounts/pipeline_items/board_index.json.jbuilder`) com o
envelope já usado por `app/views/api/v1/accounts/contacts/index.json.jbuilder`:

```ruby
json.meta do
  json.count @items_count       # total sob os filtros ativos, para o badge e o hasMore
  json.current_page @current_page
end
json.payload do
  json.array! @items do |item|
    json.partial! 'api/v1/models/pipeline_item', ... , overdue_tasks_counts: @overdue_tasks_counts
  end
end
```

**Não mexer em `index.json.jbuilder`.** `nested_pipeline_index` hoje faz `render :index`
(linha 85) e compartilha a view com o caminho "flat" (`index`, linha 10-15), consumido por
`ContactOpportunities.vue` e `ConversationOpportunities.vue`, que esperam array puro. O board
passa a renderizar a view nova; o flat continua igual.

`@items_count` é o total **com os filtros aplicados**, antes do `.page()` — é o que alimenta o
badge do cabeçalho da coluna e o `hasMore` do scroll infinito.

### 3. Filtros como params

Os 6 filtros de `store/modules/kanban/constants.js:1-7` + `showOnlyMine`. A semântica atual
está em `getters.js:59-99` e tem que ser reproduzida **exatamente**:

| Filtro | Semântica atual (`getters.js`) | No backend |
|---|---|---|
| `showOnlyMine` | `i.assignee?.id === currentUserId` (linha 71) | `where(assignee_id: Current.user.id)` |
| `assigneeId === 'unassigned'` | `!i.assignee` (linha 74) | `where(assignee_id: nil)` |
| `assigneeId` (numérico) | `i.assignee?.id === assigneeId` (linha 76) | `where(assignee_id: ...)` |
| `createdAtRange` / `updatedAtRange` | `isWithinRange` (linhas 3-9): epoch em segundos, `to` inclui o dia inteiro (`+ 86400000 - 1`) | `where(created_at: from..to)` — **cuidado com o fim do dia e com timezone** |
| `valueRange` | `min`/`max` inclusivos, `Number(i.value) || 0` (linhas 82-89) | `where(value: min..max)` |
| `labelTitles` | `.some()` → **OR**, não AND (linhas 90-94) | `tagged_with(titles, any: true)` |

O risco real aqui é divergência silenciosa: um card que aparecia some, ou vice-versa, e
ninguém percebe até um agente reclamar. Validar lado a lado antes de remover o código do
cliente (task 06/08).

### 4. Ordenação

`sort_by` (`position` | `created_at` | `updated_at` | `value` | `assignee`) + `order`
(`asc`/`desc`), default **`position` asc**. As opções vêm de `KanbanSortMenu.vue:22-26`;
`assignee` hoje ordena por `assignee.name` (`getters.js:13-15`), então no backend precisa de
`left_joins(:assignee).order('users.name')` — e `assignee` nulo tem que continuar caindo no
mesmo lado que hoje (`(a.assignee?.name || '')`, ou seja, string vazia ordena primeiro no asc).

Whitelist explícita de colunas, nunca interpolar `params[:sort_by]` em SQL. O padrão de
`SORT_OPTIONS` em `conversation_finder.rb:5-23` serve de referência.

### 5. `reorder` com offset (⚠️ risco alto)

`reorder` (`:56-72`) reindexa `position` de `0..n` a partir de `ordered_ids`:

```ruby
params[:ordered_ids].each_with_index do |item_id, index|
  # ...
  items_by_id[id]&.update_column(:position, index)
end
```

Com paginação o frontend só conhece a página carregada. Reindexar de 0 faria as posições da
página 1 colidirem com as dos cards das páginas seguintes — **a ordem do board embaralha em
produção, silenciosamente**. A action precisa aceitar um `start_position` (offset da página) e
gravar `start_position + index`. Adicionar ao `permitted_params` e documentar no Swagger.

## Testes

Docker local, com um pipeline que tenha mais cards que uma página em pelo menos duas colunas:

1. Log de query: confirmar que `GET /pipelines/:id/pipeline_items?stage_id=X&page=1` carrega
   no máximo `RESULTS_PER_PAGE` cards, e que o número de queries não cresce com o total de
   cards do pipeline.
2. `meta.count` tem que bater com o total real da coluna sob os filtros ativos — não com o
   número de cards retornados.
3. **Cada um dos 6 filtros, um a um**, comparando o resultado com o comportamento atual lado a
   lado (duas abas, uma no código antigo). Atenção especial a `labelTitles` (OR, não AND),
   `assigneeId: 'unassigned'` e ao limite superior dos ranges de data.
4. Cada opção de ordenação, asc e desc, incluindo `assignee` com cards sem responsável.
5. **Regressão de arrasto:** arrastar um card dentro da coluna e confirmar que ele **fica**
   onde foi solto (é o bug que a decisão de ordem padrão corrige); arrastar na página 2 e
   confirmar, com reload, que a página 1 não embaralhou (risco do `start_position`).

## Critério de pronto

- Board carrega no máximo `RESULTS_PER_PAGE` cards por coluna por request.
- `meta.count` reflete os filtros ativos.
- Os 6 filtros e as 5 ordenações produzem o mesmo resultado que a versão client-side.
- `reorder` com `start_position` não corrompe a ordem dos cards não carregados.
- Caminho flat (`ContactOpportunities`/`ConversationOpportunities`) inalterado — continua
  array puro.
- Nenhuma extensão correspondente em `enterprise/` (confirmar com a skill
  `sincronizar-enterprise`).
- `bundle exec rubocop -a` limpo (atenção a `Metrics/ClassLength Max: 175` — o controller vai
  crescer; se estourar, extrair os filtros para um finder/service, seguindo
  `app/finders/conversation_finder.rb`, em vez de adicionar exclude no `.rubocop.yml`).
