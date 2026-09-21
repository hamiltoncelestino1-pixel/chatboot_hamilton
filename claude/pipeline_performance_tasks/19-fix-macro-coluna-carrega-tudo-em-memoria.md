# Task 19 — Fix: macro na coluna inteira carrega todos os cards em memória

Severidade: 🟡 Média. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

A task 07 resolveu o problema certo (a macro deixou de rodar só nos cards da página carregada e
passou a ser resolvida no servidor), mas trocou uma relation limitada por uma ilimitada sem
ajustar o consumo.

`app/jobs/macros_pipeline_execution_job.rb:8-17`:

```ruby
def perform(macro, user:, pipeline_item_ids: nil, stage_id: nil, filters: {})
  account = macro.account
  items = stage_id.present? ? items_for_stage(account, stage_id, filters, user) : account.pipeline_items.where(id: pipeline_item_ids)

  return if items.blank?

  items.each do |item|
    ::Macros::PipelineExecutionService.new(macro, item, user).perform
  end
end
```

Dois pontos:

- `items.blank?` em uma `ActiveRecord::Relation` chama `records.blank?`, que **carrega a relation
  inteira** em objetos AR. Não é um `EXISTS`.
- `items.each` então itera esses objetos já materializados — todos vivos em memória ao mesmo
  tempo, durante toda a execução da macro.

Antes da task 07 o conjunto era `where(id: pipeline_item_ids)`, limitado ao que o frontend tinha
carregado (no máximo algumas dezenas). Agora `items_for_stage` devolve
`PipelineItemFinder#filtered_scope`, que é a coluna inteira sob os filtros ativos — o que era
justamente o objetivo da task. Rodar uma macro numa coluna com dezenas de milhares de cards
instancia dezenas de milhares de objetos no worker do Sidekiq de uma vez.

Nota: `filtered_scope` também não tem `includes`, e `Macros::PipelineExecutionService` toca
associações por item — o N+1 aí é pré-existente (o caminho antigo, por ids, tinha o mesmo), mas
agora acontece numa escala muito maior.

## O que corrigir

1. Trocar `items.blank?` por uma checagem que não materialize (`return unless items.exists?`, ou
   simplesmente deixar o loop não iterar se estiver vazio — conferir se o `return` antecipado
   ainda tem propósito).
2. Trocar `items.each` por `find_each` (ou `in_batches`), para processar em lotes em vez de
   carregar tudo. O projeto já usa esse padrão em job equivalente:
   `app/jobs/pipeline_items/trigger_stale_items_job.rb:5-6`
   (`find_each` no nível do pipeline e `find_each(batch_size: 100)` nos itens).
   ⚠️ `find_each` ignora `ORDER BY` (ordena por id internamente) — como aqui a ordem de execução
   da macro é irrelevante, isso não é um problema, mas conferir que `filtered_scope` não depende
   de ordem (ele já é deliberadamente "unpaginated and unordered", ver o comentário em
   `pipeline_item_finder.rb:30-32`).
3. Avaliar, no mesmo esforço, se vale acrescentar um `includes` para as associações que
   `Macros::PipelineExecutionService` realmente usa — medir antes com log de query num lote, não
   adivinhar (o mesmo cuidado da task 05 do `crm_optimizacao_tasks`, que removeu `includes` de
   associações nunca usadas).
4. Considerar se uma coluna muito grande deveria ter um teto ou uma confirmação extra na UI. Não
   é obrigatório desta task, mas vale registrar a decisão: hoje o agente clica numa macro e
   dispara N execuções sem confirmação — o rótulo mostra o número (`KANBAN.RUN_MACRO.COLUMN_ITEM_LABEL`),
   o que já é melhor que antes, mas não há "tem certeza?".

## Testes

1. Coluna com alguns milhares de cards semeados: rodar uma macro pelo cabeçalho e acompanhar a
   memória do worker (`docker stats chatwoot-noble-sidekiq-1`) antes e depois da mudança.
2. Log de query durante a execução: confirmar que os cards vêm em lotes (`LIMIT`/`WHERE id >`) e
   não num único `SELECT` gigante.
3. Confirmar que a macro atingiu **todos** os cards da coluna (contar no banco antes e depois),
   não só o primeiro lote — é o ponto inteiro da task 07, não pode regredir.
4. Rodar macro num card individual (`KanbanCard.vue`, caminho `pipeline_item_ids`) e confirmar
   que continua funcionando.
5. Coluna vazia sob os filtros ativos: o job termina sem erro e sem executar nada.

## Critério de pronto

- Nenhum ponto do job materializa a coluna inteira de uma vez.
- Macro continua atingindo todos os cards do escopo, comprovado por contagem no banco.
- Caminho por `pipeline_item_ids` intacto.
- `bundle exec rubocop -a` limpo.

## Resultado (2026-09-17)

`items.blank?` + `items.each` trocados por `items.find_each(batch_size: 100)` — sem guarda
`blank?` separada (uma relation vazia simplesmente não itera, nada a manter sincronizado). De
quebra, `app/jobs/macros_pipeline_execution_job.rb` era um dos dois arquivos com CRLF citados na
task 22 — convertido para LF aqui já que precisei tocar o arquivo mesmo (`git diff` ficou
limpo, só as linhas da task 07 + desta).

**Item 3 (includes): medido, não adicionado.** Rodei a macro real (`assign_pipeline_item_agent`)
contra 20 cards com/sem `.includes(:contact, :conversation, :assignee, :team, pipeline_stage:
:pipeline)` na relation inicial: **303 queries sem `includes` vs. 304 com** — nenhuma economia,
dentro do ruído. Motivo: `Macros::PipelineExecutionService#perform` chama `@pipeline_item.reload`
antes de **cada** ação (comentário no próprio arquivo explica por quê), o que descarta qualquer
association pré-carregada antes da primeira ação rodar. `includes` na relation do job é
literalmente inofensivo aqui — não vale adicionar.

O N+1 real (confirmado, ~15 queries/item) não vem da lógica da macro em si, vem do **broadcast
síncrono por item**: cada `update!` dispara `pipeline_item_updated` → `ActionCableListener`
(síncrono, via `SyncDispatcher`) → `push_event_data` (avatar do contato/responsável, tags do
card) **e** a resolução de tokens da task 12 (`pipeline_item.pipeline.members`). É estrutural —
batching de broadcast para operação em lote é uma mudança de arquitetura, não um `includes`.
Fora do escopo desta task; registrado aqui para não ser confundido com "resolvido".

Testado no Docker local:
1. **Volume**: 3.000 cards semeados via SQL bruto num único stage; job rodou em ~46s, **31
   SELECTs em lote** (`ORDER BY id ASC LIMIT`) de até 100 linhas cada — nunca uma única query
   carregando os 3.000 de uma vez.
2. **Cobertura total**: 3.000/3.000 cards receberam a ação (contado no banco depois) — o ponto
   da task 07 não regrediu.
3. **Caminho `pipeline_item_ids`**: rodei com uma lista de 2 ids entre 3 cards — só os 2 alvos
   foram atualizados, o terceiro ficou intacto.
4. **Relation vazia** (filtro de responsável impossível): job terminou sem erro, nada executado.

`bundle exec rubocop -a`: limpo. `bundle exec rspec` (macros/pipeline_execution_service +
pipeline_item_actions): 26/26 passando. Dados de teste (pipelines, contatos, macro) removidos
depois de cada rodada.
