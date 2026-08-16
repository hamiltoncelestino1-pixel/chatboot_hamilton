# Task 04 — Padronizar: join redundante em vez da coluna `pipeline_id` direta

Severidade: 🟠 Alta. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

A migration `db/migrate/20260731130000_add_pipeline_id_to_pipeline_items.rb` adicionou
`pipeline_id` como FK própria em `pipeline_items` exatamente para permitir filtrar/indexar
diretamente, sem precisar fazer `JOIN` com `pipeline_stages` — o comentário em
`app/models/pipeline_item.rb:49-52` documenta essa intenção explicitamente.

Apesar disso, hoje o próprio código está inconsistente: `PipelineItemsController#create`
(linha 29) e `#reorder` (linha 66) já usam a coluna direta corretamente, mas **4 outros
pontos** ainda fazem o join desnecessário:

1. `app/controllers/api/v1/accounts/pipeline_items_controller.rb:16` (`index`):
   ```ruby
   items = policy_scope(
     Current.account.pipeline_items
            .joins(:pipeline_stage)
            .where(pipeline_stages: { pipeline_id: policy_scope(Current.account.pipelines).select(:id) })
            ...
   ```
2. `app/controllers/api/v1/accounts/pipeline_items_controller.rb:95` (`fetch_item`):
   ```ruby
   @item = policy_scope(
     Current.account.pipeline_items
            .joins(:pipeline_stage)
            .where(pipeline_stages: { pipeline_id: allowed_pipeline_ids })
            ...
   ```
3. `app/controllers/api/v1/accounts/pipeline_items/labels_controller.rb:14-15` (`fetch_item`)
   — mesmo padrão de join.
4. `app/controllers/api/v1/accounts/macros_controller.rb:74-75`
   (`authorized_pipeline_item_ids`) — mesmo padrão de join.

Isso é uma inconsistência real dentro do próprio arquivo `pipeline_items_controller.rb`
(2 métodos usam a coluna certa, 2 fazem join), e desperdiça a otimização que a migration foi
desenhada para entregar — mais impactante em `index`, que é o endpoint mais chamado pelo
Kanban.

## O que corrigir

Nos 4 pontos listados, trocar `.joins(:pipeline_stage).where(pipeline_stages: { pipeline_id:
X })` por `.where(pipeline_id: X)`, usando a coluna direta de `pipeline_items`.

**Cuidado**: em `pipeline_items_controller.rb:16` (`index`), o `.joins(:pipeline_stage)`
pode estar ali só por causa do filtro de `pipeline_id`, ou pode haver alguma dependência
implícita de ordenação/seleção de colunas da stage — ler o método inteiro antes de remover o
join, para não quebrar nada que dependa dele silenciosamente (ex. `.includes(pipeline_stage:
:pipeline)` já presente na linha 17 continua necessário para a serialização, isso não muda).

## Testes

Como esses 4 pontos decidem o que o usuário pode ver/acessar (autorização por escopo de
pipeline), validar manualmente que o resultado retornado é **idêntico** antes/depois da
mudança: mesmo conjunto de `pipeline_items` visíveis para o mesmo usuário, nos 4 endpoints
afetados (listagem de cards, busca de card único, labels de card, execução de macro em
lote). Testar tanto com um usuário admin quanto um agente membro de só alguns pipelines
(para garantir que o escopo de `assigned_pipelines` continua sendo respeitado).

## Critério de pronto

- Os 4 pontos usam `.where(pipeline_id: ...)` em vez de `.joins(:pipeline_stage).where(pipeline_stages: {...})`.
- Resultado de autorização/filtro idêntico ao anterior (confirmado manualmente com pelo
  menos 2 perfis de usuário diferentes).
- `bundle exec rubocop -a` limpo nos arquivos tocados.
