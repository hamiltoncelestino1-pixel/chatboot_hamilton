# Task 04 — Swagger da rota paginada do board

Severidade: 🟡 Média. Achado na análise de performance de 2026-09-15.
Depende da task 03.

## Objetivo

A task 03 muda o contrato de `GET /api/v1/accounts/{account_id}/pipelines/{pipeline_id}/pipeline_items`:
de array puro para `{ meta, payload }`, com novos parâmetros de query (`page`, `stage_id`
obrigatório, 6 filtros, `sort_by`, `order`) — e `POST /pipeline_items/reorder` ganha
`start_position`.

`swagger/paths/application/pipelines/items/index.yml` hoje declara array puro:

```yaml
description: List all items for a given pipeline. Pass ?stage_id=X to filter by stage.
responses:
  '200':
    content:
      application/json:
        schema:
          type: array
          items:
            $ref: '#/components/schemas/pipeline_item'
```

**Armadilha:** esse mesmo arquivo é referenciado por dois paths diferentes em
`swagger/paths/index.yml`:

```yaml
576:/api/v1/accounts/{account_id}/pipelines/{pipeline_id}/pipeline_items:
581:    $ref: ./application/pipelines/items/index.yml
587:/api/v1/accounts/{account_id}/pipeline_items/{pipeline_item_id}:
592:    $ref: ./application/pipelines/items/index.yml
```

A linha 592 é o `GET` de **um** item (o `show`), que já aponta para o arquivo errado hoje.
Editar `index.yml` no lugar mudaria também a documentação do `show`. Além disso o caminho flat
`/api/v1/accounts/{account_id}/pipeline_items` (linha 582) continua devolvendo array puro e
não pode herdar o envelope.

Specs de `type: :request` são validadas contra `swagger/swagger.json` pelo Skooma
(`spec/rails_helper.rb:79-81`). Hoje não há spec cobrindo o `index`
(`spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` só cobre `create` e
`export`), então nada quebra automaticamente — o que torna esta task mais fácil de esquecer e
não menos necessária.

## O que corrigir

1. Criar um YAML novo para o caminho do board (ex.
   `swagger/paths/application/pipelines/items/board_index.yml`) com: os parâmetros de query da
   task 03, e o schema de resposta `{ meta: { count, current_page }, payload: [pipeline_item] }`.
   **Não** editar `index.yml`, que continua servindo o caminho flat.
2. Em `swagger/paths/index.yml`, apontar a linha 581 para o arquivo novo e deixar 592 como
   está (corrigir o `$ref` errado do `show` é um achado à parte — anotar, não misturar nesta
   task).
3. Atualizar `swagger/paths/application/pipelines/items/reorder.yml` com `start_position`.
4. Rodar `bundle exec rails swagger:build` (no container:
   `docker exec chatwoot-noble-rails-1 bundle exec rails swagger:build`) e commitar o
   `swagger/swagger.json` gerado junto.
5. Conferir no Swagger UI que os dois endpoints aparecem separados e com os schemas certos —
   a regra de memória do projeto sobre deploy de endpoints vale aqui: JSON correto não garante
   que apareça na UI.

## Testes

- `bundle exec rails swagger:build` roda sem erro e o diff do `swagger.json` contém as duas
  mudanças (board index + reorder).
- Abrir o Swagger UI e conferir que o path do board mostra os parâmetros de filtro/ordenação e
  o envelope, e que o path flat continua mostrando array.
- `bundle exec rspec spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` —
  continua verde (Skooma valida `create`/`export` contra o YAML; nada deve ter mudado ali).

## Critério de pronto

- Caminho do board documentado com envelope e todos os parâmetros novos.
- Caminho flat e `show` **não** alterados.
- `reorder.yml` com `start_position`.
- `swagger/swagger.json` regenerado e commitado.
- Endpoints visíveis e corretos no Swagger UI.
