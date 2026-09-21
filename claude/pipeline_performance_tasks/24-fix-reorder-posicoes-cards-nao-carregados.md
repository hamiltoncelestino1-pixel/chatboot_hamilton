# Task 24 — Fix: reordenar a página 1 joga os cards não carregados para o topo

Severidade: 🟠 Alta. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).
⚠️ Exige decisão de produto antes de codar.

## Objetivo

É a "Observação relacionada" da [task 14](14-fix-ordenacao-sem-desempate.md) chegando: aquela
task resolveu a **leitura** (paginação determinística), esta é sobre a **escrita**.

`KanbanColumn.vue` despacha o reorder sem `startPosition`:

```js
const onEnd = ({ from, to }) => {
  if (from !== to) return;
  if (isSortActive.value) { localItems.value = [...storeItems.value]; return; }
  const orderedIds = localItems.value.map(i => i.id);
  store.dispatch('kanban/reorderItems', {
    stageId: props.stage.id,
    orderedIds,
  });
};
```

`reorderItems` default para `startPosition = 0` (`actions.js`), e
`PipelineItemsController#reposition_items` grava `start_position + index` **só nos ids
recebidos**:

```ruby
def reposition_items(stage, start_position)
  items_by_id = stage.pipeline_items.index_by(&:id)
  visible_item_ids = policy_scope(stage.pipeline_items).pluck(:id)

  params[:ordered_ids].each_with_index do |item_id, index|
    id = item_id.to_i
    next unless visible_item_ids.include?(id)

    items_by_id[id]&.update_column(:position, start_position + index)
  end
end
```

Isso está **correto** para o prefixo carregado — ele sempre começa em 0 e as páginas são
contíguas. O problema são os cards **não carregados**, que mantêm a `position` antiga:

- `pipeline_items.position` tem `default: 0` (`db/schema.rb`) e **nada atribui uma posição na
  criação** — `create_params` aceita `:position`, mas `AddItemModal.vue` não envia, e automação/
  macro também não.
- Confirmado no banco de dev: **15 de 21 cards estão com `position = 0`**.

Repro, coluna com 30 cards todos em `position 0`, ordenação manual (o padrão desde a task 03):

1. Página 1 traz 25 (desempate por `id`, task 14).
2. Agente arrasta um card dentro da coluna → esses 25 passam a ter `position` `0..24`.
3. Os 5 restantes continuam em `position = 0`.
4. No próximo carregamento (`ORDER BY position asc, id asc`) os 5 vêm **na frente de tudo** —
   cards que o agente nunca tocou pulam para o topo da coluna.

Mecanicamente o comportamento é pré-existente (o `reorder` sempre reindexou a partir de 0, e os
cards sempre nasceram em 0), mas era **invisível**: antes da task 15 o arrasto nem surtia efeito,
e antes da task 03 a ordem padrão era `created_at desc`. Agora ordem manual é o padrão e o
arrasto funciona, ou seja, é o fluxo principal do board.

## O que corrigir

Escolher uma das duas saídas — não fazer as duas:

1. **Atribuir `position` na criação (recomendado).** Todo card novo nasce no fim (ou no começo)
   da sua stage em vez de empatar em 0. Resolve a causa-raiz: o `reorder` do prefixo passa a ser
   consistente porque os não carregados têm posições **maiores** que as do prefixo, não iguais a
   zero. Pontos de entrada a cobrir: `PipelineItemsController#create`, `Pipelines::ExportItemService`
   (card que chega de outro pipeline), e as ações de automação/macro que criam ou movem card
   (`app/services/concerns/pipeline_item_actions.rb`). Decidir se entra como callback no model
   (`before_create`) para pegar todos de uma vez — provavelmente sim, é o único jeito de não
   esquecer um caminho.
   ⚠️ Precisa de **migração de dados** para os cards já existentes em `position = 0`, senão o
   problema continua no legado. Backfill por stage, na ordem atual (`position, id`).
2. **Normalizar a stage inteira no `reorder`.** A action passa a reindexar todos os cards da
   stage, aplicando a permutação recebida ao prefixo e empurrando o resto para depois. Mais
   contido (um arquivo), mas transforma cada arrasto numa escrita `O(n)` na coluna inteira — numa
   coluna de 50k cards isso é um `UPDATE` por card a cada drag. Só vale se a opção 1 for
   descartada.

Em qualquer uma das saídas, `start_position` continua fazendo sentido e não deve ser removido —
ele é o contrato que permite reordenar uma página que não começa em 0 (task 03, risco 1).

## Testes

1. Coluna com mais de uma página de cards, **todos em `position = 0`** (é o estado real de quem
   criou cards pela UI): arrastar um card na página 1, recarregar o board, e confirmar que
   **nenhum card não tocado pulou para o topo**.
2. Repetir com a coluna já toda carregada (rolar até o fim antes de arrastar) — tem que continuar
   funcionando igual.
3. Criar um card novo pelo modal e confirmar onde ele aparece, antes e depois de um refetch — o
   lugar tem que ser o mesmo (interage com a [task 28](28-fix-ordem-insercao-destoa-ordem-manual.md)).
4. Card que chega por `Pipelines::ExportItemService` e card criado por automação/macro: mesma
   verificação do item 3.
5. Se a saída 1 for escolhida: rodar o backfill no Docker local com dados semeados e conferir que
   cada stage ficou com posições únicas e contíguas, sem alterar a ordem que já era exibida.
6. Arrastar entre colunas continua funcionando, e a ordem persiste após reload.

## Critério de pronto

- Arrastar dentro de uma coluna paginada não muda a posição relativa de nenhum card que o agente
  não tocou.
- Cards novos (UI, export, automação, macro) nascem com `position` própria, não empatada em 0.
- Legado migrado (se a saída 1 for escolhida) — o fix não pode valer só para cards novos.
- `start_position` preservado.
- Saída escolhida e justificativa registradas neste arquivo.
- `bundle exec rubocop -a` e `pnpm eslint` limpos.

## Decisão e resultado (2026-09-18)

**Saída 1 (recomendada)**: atribuir `position` na criação, via `before_create :assign_position,
unless: :position_changed?` em `PipelineItem` — pega os dois pontos de criação reais do projeto
(`PipelineItemsController#create` e `ConversationPipelineActions#create_pipeline_item`, usado por
automação/macro; confirmei que não há nenhum outro `PipelineItem.create`/`.new` em `app/` nem
`enterprise/`). `Pipelines::ExportItemService` não cria registro novo (só move um existente via
`update!`), então fica de fora do callback mas usa a mesma lógica.

Consolidei a query `(stage.pipeline_items.maximum(:position) || -1) + 1`, que já existia
**duplicada três vezes** (`PipelineItemActions#next_position_for_stage`,
`ExportItemService#next_position`, e agora o callback), num único `PipelineStage#next_position`
— os três call sites passaram a usar `stage.next_position`.

**Backfill**: migration `20260918120000_backfill_pipeline_items_position.rb`, renumerando cada
stage `0..n-1` via `ROW_NUMBER() OVER (PARTITION BY pipeline_stage_id ORDER BY position, id)` — a
mesma ordem `(position, id)` que a task 14 já usa pra desempate na leitura, então a ordem exibida
não muda, só os valores empatados se espalham.

`start_position` não foi tocado (segue existindo em `reorderItems`/`reposition_items`).

**Achado incidental**: ao rodar rubocop nos arquivos tocados (`pipeline_stage.rb`,
`export_item_service.rb`, `pipeline_item_actions.rb`), os três estavam com CRLF (igual às tasks
22/29, sem relação com esta task) — corrigidos de passagem. Dois outros achados do rubocop nesses
arquivos ficaram de fora por serem pré-existentes e fora de escopo: uma linha de anotação de
schema (`pipeline_item.rb:36`, gerada pela gem `annotate`, já excedia 150 chars antes desta task)
e `Rails/InverseOf` em `pipeline_stage.rb:25` (design pré-existente da associação, não
introduzido aqui).

## Validação (Docker local, dados reais + reprodução do bug original)

1. **Estado real antes do backfill**: 15 de 21 cards em `position = 0` — bate exatamente com o
   número citado na task.
2. **Backfill**: capturei a ordem de exibição (`position, id`) de todas as 13 stages **antes** da
   migration, rodei a migration, e confirmei que a ordem exibida ficou **idêntica** em todas as
   13 — só os valores de `position` mudaram (agora únicos e contíguos `0..n-1` em toda stage).
3. **Callback em card novo**: criei 3 cards numa stage nova (posições `0,1,2`) e um 4º sem
   `position` explícita — foi pro fim (`3`), não para `0`.
4. **`move_stage` (automação/macro)**: usei o concern diretamente — card movido para uma stage
   vazia ficou em `position = 0` (correto, via `stage.next_position` compartilhado).
5. **Reprodução completa do bug original**: semeei 30 cards (posições únicas de fábrica agora),
   simulei a página 1 (25 cards) e arrastei o último card da página 1 pro topo — os 5 cards da
   "página 2" (não carregados/não tocados) **permaneceram no lugar, depois da página 1**, sem
   pular para o topo. Card arrastado foi pro topo corretamente, resto da página 1 manteve a
   ordem relativa.

`bundle exec rubocop -a`: limpo (exceto os 2 achados pré-existentes fora de escopo, acima).
`bundle exec rspec` (pipeline_item + pipeline_items_controller + pipeline_item_actions +
macros/pipeline_execution_service): 58/58 passando — a nova callback não quebrou nenhum spec
existente (a factory não define `position`, então specs que criam via factory passaram a receber
posições sequenciais em vez de `0`, sem que nenhum teste dependesse do valor antigo).
