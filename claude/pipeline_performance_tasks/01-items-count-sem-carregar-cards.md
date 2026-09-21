# Task 01 — `items_count` carrega todos os cards de todos os pipelines

Severidade: 🔴 Crítico. Achado na análise de performance de 2026-09-15.

## Objetivo

É o **pior gargalo do board**, e acontece no primeiro request, antes de qualquer card ser
pedido: `KanbanIndex.vue:51-53` dispara `fetchPipelines` no `onMounted`.

`app/controllers/api/v1/accounts/pipelines_controller.rb`:

```ruby
def index                                              # linha 5
  @pipelines = policy_scope(Current.account.pipelines).includes(pipeline_stages: :pipeline_items)
end
# ...
def fetch_pipeline                                     # linha 27
  @pipeline = policy_scope(Current.account.pipelines).includes(pipeline_stages: :pipeline_items).find(params[:id])
end
```

`app/controllers/api/v1/accounts/pipeline_stages_controller.rb:7`:

```ruby
def index
  @stages = @pipeline.pipeline_stages.includes(:pipeline_items)
end
```

O `includes` existe só por causa de `app/views/api/v1/models/_pipeline_stage.json.jbuilder:8`:

```ruby
json.items_count resource.pipeline_items.size
```

Resultado: para renderizar um número por stage, o Rails instancia **todo `PipelineItem` de
todo pipeline da conta** como objeto ActiveRecord. Com 50k cards são 50k objetos alocados por
request — e o payload de `/pipelines` continua pequeno, então o custo é invisível no
DevTools e aparece só como "o board demora pra abrir".

Origem: `claude/crm_optimizacao_tasks/03-fix-items-count-nplus1-pipelines.md` trocou N queries
`COUNT` por este eager load. Foi a decisão certa naquele volume e é a errada neste — a task
não está sendo revertida por estar errada, está sendo substituída por uma solução que escala.

## O que corrigir

1. Remover `includes(pipeline_stages: :pipeline_items)` de `pipelines_controller.rb:6` e `:28`
   (manter `includes(:pipeline_stages)`, que continua necessário) e `includes(:pipeline_items)`
   de `pipeline_stages_controller.rb:7`.
2. Calcular a contagem em **1 query agregada por listagem**:
   `PipelineItem.where(pipeline_stage_id: <ids das stages sendo renderizadas>).group(:pipeline_stage_id).count`,
   e passar o hash resultante ao partial via `local_assigns`, exatamente como
   `@overdue_tasks_counts` já é passado em
   `app/views/api/v1/accounts/pipeline_items/index.json.jbuilder:3` e lido em
   `_pipeline_item.json.jbuilder:38`.
3. `_pipeline_stage.json.jbuilder:8` passa a ler do hash, com fallback:
   `local_assigns[:items_counts]&.fetch(resource.id, 0) || 0`. Atenção: o partial é renderizado
   por mais de um caminho (`pipelines/index`, `pipelines/show`, `pipeline_stages/index`,
   `create`, `update`) — **todos** precisam passar o local, ou algum vai passar a mostrar `0`
   em vez do número certo. Esse é exatamente o bug que a
   `claude/crm_features_fixes_tasks/04-*.md` corrigiu para `overdue_tasks_count`; não repetir
   o mesmo erro aqui. Para os caminhos de card único (`create`/`update` de stage), montar um
   hash de uma chave só é aceitável.

**Por que contagem agregada e não `counter_cache`:** um `counter_cache` na coluna
`pipeline_stages.items_count` seria mais barato ainda, mas guarda só o total bruto. A task 03
precisa que o contador do cabeçalho da coluna reflita **os filtros ativos** — uma contagem
agregada aceita as mesmas cláusulas `where` da listagem, um counter_cache não. Além disso,
counter_cache exige migração + backfill e passa a depender de callbacks em pontos que hoje
usam `update_column` (`pipeline_items_controller.rb:69`).

## Testes

Docker local, com pelo menos alguns milhares de cards semeados:

1. Ligar o log de query do Rails, abrir o board e medir `GET /api/v1/accounts/:id/pipelines`
   antes e depois. Critério: número de queries **constante** (não cresce com stages nem com
   cards), e nenhuma query `SELECT ... FROM pipeline_items` que retorne linhas de card
   completas nesse request.
2. Conferir que `items_count` continua com **exatamente os mesmos valores** de antes, nos 5
   caminhos que renderizam o partial de stage: lista de pipelines, detalhe de pipeline, lista
   de stages, criação de stage e edição de stage.
3. Conferir a contagem exibida em `Configurações → Pipelines` (`PipelineStagesSection.vue`) —
   hoje ela vem do store, não daqui, mas a task 07 vai migrar para `stage.items_count`, então
   o valor precisa estar certo na API.

## Critério de pronto

- `GET /pipelines`, `GET /pipelines/:id` e `GET /pipelines/:id/pipeline_stages` não
  instanciam mais `PipelineItem`.
- `items_count` continua correto em todos os caminhos que renderizam
  `_pipeline_stage.json.jbuilder`, inclusive nos de card único.
- 1 query agregada por listagem, não 1 por stage (não reintroduzir o N+1 original).
- Nenhuma extensão correspondente em `enterprise/` (confirmar com a skill
  `sincronizar-enterprise`).
- `bundle exec rubocop -a` limpo nos arquivos tocados.
