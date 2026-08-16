# Task 03 — Fix: N+1 de `items_count` em `PipelinesController#index`/`show`

Severidade: 🟠 Alta. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`app/views/api/v1/models/_pipeline_stage.json.jbuilder:8` chama
`resource.pipeline_items.size`, disparando um `COUNT(*) FROM pipeline_items WHERE
pipeline_stage_id = ?` por stage sempre que a associação não estiver pré-carregada.

Dois pontos de entrada acionam esse partial sem pré-carregar `pipeline_items`:

- `app/controllers/api/v1/accounts/pipelines_controller.rb:6`:
  ```ruby
  def index
    @pipelines = policy_scope(Current.account.pipelines).includes(:pipeline_stages)
  end
  ```
  Só inclui `:pipeline_stages`, não `pipeline_items` dentro delas — para cada stage de
  cada pipeline listado, dispara um `COUNT` separado.

- `app/views/api/v1/accounts/pipelines/show.json.jbuilder:2-4` — mesmo problema no `show`
  de um único pipeline (itera `@pipeline.pipeline_stages` sem eager load de `pipeline_items`).

O fix já existe no arquivo irmão, resolvendo exatamente o mesmo problema:
`PipelineStagesController#index` (`app/controllers/api/v1/accounts/pipeline_stages_controller.rb:7`):

```ruby
def index
  @stages = @pipeline.pipeline_stages.includes(:pipeline_items)
end
```

## O que corrigir

1. `pipelines_controller.rb#index` (linha 6): trocar
   `.includes(:pipeline_stages)` por `.includes(pipeline_stages: :pipeline_items)`.
2. `show.json.jbuilder`: garantir que o `@pipeline` carregado em
   `fetch_pipeline` (`pipelines_controller.rb:27-29`) também pré-carregue
   `pipeline_stages: :pipeline_items` antes de renderizar — ajustar `fetch_pipeline` (é
   usado por `show`/`update`/`destroy`, então confirmar que o eager load extra não pesa
   desnecessariamente nas outras 2 actions; se for um problema, pode-se limitar o
   `includes` só ao caminho de `show` via um scope separado, mas o caminho mais simples é
   incluir sempre — `update`/`destroy` não usam `pipeline_stages` na resposta hoje, então
   o custo extra ali é irrelevante).

## Testes

Testar manualmente no Docker local: abrir a lista de pipelines/boards do Kanban com pelo
menos 2 pipelines e várias stages cada, e confirmar (via log de query do Rails, `rails
console` com `ActiveRecord::Base.logger` ativo, ou `bullet` gem se disponível) que o número
de `COUNT` queries não escala mais linearmente com o número de stages.

## Critério de pronto

- `PipelinesController#index` e `show.json.jbuilder` não geram mais 1 `COUNT` por stage.
- Resposta JSON de `items_count` continua com os mesmos valores de antes.
- `bundle exec rubocop -a` limpo nos arquivos tocados.
