# Task 02 — Fix: `reorder` de card do Kanban faz 2N queries

Severidade: 🟠 Alta. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`PipelineItemsController#reorder` (`app/controllers/api/v1/accounts/pipeline_items_controller.rb:62-75`):

```ruby
def reorder
  allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
  stage = Current.account.pipeline_stages
                 .joins(:pipeline)
                 .where(pipeline_id: allowed_pipeline_ids)
                 .find(params[:stage_id])
  visible_item_ids = policy_scope(stage.pipeline_items).pluck(:id)
  params[:ordered_ids].each_with_index do |item_id, index|
    next unless visible_item_ids.include?(item_id.to_i)

    stage.pipeline_items.find(item_id).update_column(:position, index)
  end
  head :ok
end
```

`visible_item_ids` já valida quais ids são permitidos (via `pluck`), mas dentro do loop
`stage.pipeline_items.find(item_id)` dispara um novo `SELECT` por card — mesmo já sabendo
que o id é válido — seguido de um `UPDATE` isolado via `update_column`. Um reorder de uma
coluna com N cards custa **2N queries** no banco a cada drag-and-drop no Kanban.

O padrão correto já existe no arquivo vizinho, resolvendo exatamente o mesmo problema:
`PipelineStagesController#reorder` (`app/controllers/api/v1/accounts/pipeline_stages_controller.rb:30-44`):

```ruby
def reorder
  ordered_ids = params[:ordered_ids].map(&:to_i)
  stages_by_id = @pipeline.pipeline_stages.index_by(&:id)
  # ... classificação em grupos ...
  normalized.each_with_index do |stage_id, index|
    stages_by_id[stage_id]&.update_column(:position, index)
  end
  head :ok
end
```

Pré-carrega tudo com `index_by(&:id)` numa única query, e o loop só faz `update_column` (sem
`SELECT` extra por iteração).

## O que corrigir

Replicar o mesmo padrão em `PipelineItemsController#reorder`: carregar os registros de uma
vez, indexados por id, e usar esse hash dentro do loop em vez de `.find` repetido.

```ruby
def reorder
  allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
  stage = Current.account.pipeline_stages
                 .joins(:pipeline)
                 .where(pipeline_id: allowed_pipeline_ids)
                 .find(params[:stage_id])
  items_by_id = stage.pipeline_items.index_by(&:id)
  visible_item_ids = policy_scope(stage.pipeline_items).pluck(:id)

  params[:ordered_ids].each_with_index do |item_id, index|
    id = item_id.to_i
    next unless visible_item_ids.include?(id)

    items_by_id[id]&.update_column(:position, index)
  end
  head :ok
end
```

Manter o `pluck` de `visible_item_ids` separado (é a checagem de autorização via
`policy_scope`, não misturar com o carregamento de dados) — só eliminar o `.find` repetido
dentro do loop.

## Testes

Testar manualmente no Docker local: arrastar vários cards seguidos numa coluna do Kanban com
pelo menos 5-10 cards, confirmar que a ordem persiste corretamente após reload da página (não
só visualmente antes de recarregar).

## Critério de pronto

- Loop de `reorder` não dispara mais `SELECT` por iteração — só o `UPDATE`.
- Reorder de cards no Kanban continua funcionando exatamente igual (mesma ordem final,
  mesma autorização respeitada).
- `bundle exec rubocop -a` limpo no arquivo tocado.
