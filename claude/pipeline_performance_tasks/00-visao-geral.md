# Visão Geral — Performance dos Pipelines (Kanban) em alto volume

## Objetivo

Com volume alto de cards, abrir o board Kanban trava e demora a carregar. A hipótese inicial
(paginar o carregamento igual às conversas) está correta, mas a análise mostrou que **a
paginação sozinha não resolve o pior gargalo** — e que ela não é um patch, é uma mudança de
arquitetura, porque hoje filtro e ordenação são 100% client-side e só funcionam porque todos
os cards estão no navegador.

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task independente.
Nenhuma task foi implementada ainda. Plano de origem: análise de viabilidade de 2026-09-15.

## Como esta análise foi feita

Leitura direta ponta a ponta do domínio Pipeline/Kanban (models, controllers, policies,
jbuilders, schema, listener de ActionCable, jobs, store Vuex, componentes do board) +
comparação com o caminho equivalente já otimizado das conversas/contatos. Nenhum item abaixo
é especulativo: todo achado cita o arquivo e a linha que o comprova.

## Diagnóstico — as 3 camadas do problema

### 1. O primeiro request do board já carrega o banco inteiro (pior gargalo)

`KanbanIndex.vue:53` dispara `fetchPipelines` **antes** de qualquer card.
`PipelinesController#index` (`app/controllers/api/v1/accounts/pipelines_controller.rb:6`) faz:

```ruby
policy_scope(Current.account.pipelines).includes(pipeline_stages: :pipeline_items)
```

Isso instancia **todo `PipelineItem` de todo pipeline da conta** como objeto ActiveRecord —
só para `app/views/api/v1/models/_pipeline_stage.json.jbuilder:8` renderizar
`resource.pipeline_items.size`. Com 50k cards, são 50k objetos por request. Mesmo problema em
`fetch_pipeline` (`pipelines_controller.rb:28`, usado por `show`/`update`/`destroy`) e em
`PipelineStagesController#index:7`.

Isso veio de `claude/crm_optimizacao_tasks/03-fix-items-count-nplus1-pipelines.md`, que trocou
N queries `COUNT` por um eager load — a decisão certa no volume de então, e a errada neste
volume. Não é um erro daquela task; é o ponto em que a solução dela deixou de escalar.

### 2. Dois N+1 por card na serialização

`app/views/api/v1/models/_pipeline_item.json.jbuilder` renderiza, por card:

- linha 36 → `resource.label_list` (`Labelable`/acts_as_taggable_on,
  `app/models/concerns/labelable.rb:5`). Nenhum dos três scopes do `PipelineItemsController`
  (linhas 99, 111, 118) faz eager load de taggings/tags.
- linha 19 → `resource.contact.avatar_url` → `Avatarable#avatar_url:16`, que chama
  `avatar.attached?` + `representable?` + `url_for(representation)`. Sem
  `contact: { avatar_attachment: :blob }`, são 2-3 queries extras por card.

O projeto já resolve os dois no caminho das conversas: `app/finders/conversation_finder.rb:202`
inclui `:taggings` e os dois `avatar_attachment: [:blob]`. Os pipelines nunca receberam esse
tratamento.

### 3. Nenhum limite, e recomputação global no frontend

- `nested_pipeline_index` (`pipeline_items_controller.rb:80-86`) devolve **todos** os cards do
  pipeline, sem `page`/`limit`.
- `getFilteredSortedItemsForStage` (`store/modules/kanban/getters.js:59`) é um getter
  *method-style* — Vuex não cacheia getters que retornam função. Ele re-executa filtro +
  `[...items].sort()` a cada acesso e devolve **sempre um array novo**. `KanbanColumn.vue:23-30`
  o consome num `computed` + `watch`, então **qualquer** mutação no store (um push de
  ActionCable, um flag de UI) re-filtra e re-ordena os cards de **todas** as colunas e força o
  `vuedraggable` a re-renderizar a coluna inteira.
- Zero virtualização: cada card são ~40 nós de DOM (`KanbanCard.vue`), todos montados.
- `KanbanCard.vue:31` chama `store.getters['attributes/getAttributesByModel']` por card, e esse
  getter faz `.filter()` no array inteiro de atributos (`store/modules/attributes.js:33-37`).
- `$state.items` acumula cards de todos os pipelines já visitados: `SET_ACTIVE_PIPELINE`
  (`mutations.js:150-153`) limpa `itemOrder` mas **não** `items`. `getItemsForContact`/
  `getItemsForConversation` (`getters.js:101-107`) varrem esse dicionário inteiro.

### Achado colateral confirmado

O board sempre reordena por `created_at desc` no cliente e ignora a coluna `position`.
Arrastar um card dentro da coluna persiste `position` no banco (`actions.js:198` → `reorder`),
mas `watch(storeItems)` reordena de volta e o card volta pro lugar. **Arrastar para reordenar
dentro da coluna está quebrado hoje** — a task 03 corrige isso como efeito da ordenação
server-side.

## Decisões de produto já tomadas (2026-09-15)

1. **Paginação por coluna com scroll infinito**, reusando `IntersectionObserver.vue` (o mesmo
   de `ConversationList.vue:88`). Filtro e ordenação migram para o backend.
2. **Escopo cheio**: paginação + gargalos de backend + gargalos de frontend.
3. **Ordem padrão da coluna passa a ser `position`**, corrigindo o arrasto. As opções do
   `KanbanSortMenu` continuam existindo como override explícito.

## Ordem de execução recomendada

| # | Task | Severidade | Área | Depende de |
|---|------|------------|------|------------|
| [01](01-items-count-sem-carregar-cards.md) | `items_count` carrega todos os cards de todos os pipelines | 🔴 Crítico | Backend/Pipeline | — |
| [02](02-nplus1-labels-e-avatar-pipeline-item.md) | N+1 de `label_list` e de `avatar_url` por card | 🔴 Crítico | Backend/Pipeline | — |
| [03](03-backend-paginacao-filtro-sort-server-side.md) | Paginação + filtro + ordenação server-side no board | 🟠 Alta | Backend/Pipeline | 02 |
| [04](04-swagger-rota-paginada.md) | Swagger da rota paginada | 🟡 Média | Backend/Docs | 03 |
| [05](05-store-estado-por-stage.md) | Store Vuex: estado de paginação por stage | 🟠 Alta | Frontend/Pipeline | 03 |
| [06](06-ui-scroll-infinito-por-coluna.md) | UI: scroll infinito por coluna + filtros server-side | 🟠 Alta | Frontend/Pipeline | 05 |
| [07](07-consumidores-tudo-carregado.md) | Consertar consumidores que assumem "tudo carregado" | 🟠 Alta | Frontend/Pipeline | 05 |
| [08](08-desmontar-getter-global.md) | Desmontar o getter global de filtro/sort | 🟠 Alta | Frontend/Pipeline | 06 |
| [09](09-atributos-customizados-fora-do-card.md) | `getAttributesByModel` recalculado por card | 🟡 Média | Frontend/Pipeline | — |
| [10](10-memoria-do-store-kanban.md) | `$state.items` cresce indefinidamente | 🟡 Média | Frontend/Pipeline | 05 |
| [11](11-opcional-virtualizar-coluna.md) | (Opcional) Virtualizar a coluna com `virtua` | 🟢 Baixa | Frontend/Pipeline | 08 |
| [12](12-escopar-broadcast-pipeline-item.md) | Broadcast de pipeline item vai pra conta inteira | 🟠 Alta | Backend/Realtime | — |
| [13](13-indice-cron-stale-items.md) | Cron de card parado sem índice que sirva | 🟢 Baixa | Backend/DB | — |

**Grupo A** (01-02) = quick wins de backend, sem mudar contrato de API. **Devem ser feitas
primeiro e medidas isoladamente** — é o ganho que aparece sozinho, antes de qualquer
paginação, e pode ser que já resolva boa parte da dor.

**Grupo B** (03-07) = a paginação ponta a ponta. Sequência obrigatória, não paralelizável
entre si — 03 muda o contrato da API, 05 consome o contrato novo, 06 e 07 consomem o store novo.

**Grupo C** (08-11) = performance de interação (o travamento ao mexer no board, não ao
carregar). 09 é independente e pode ser feita a qualquer momento. 11 só se ainda travar
depois de tudo.

**Grupo D** (12-13) = escala e infra, independentes do resto, podem ser paralelizadas.

## Correções pós-implementação — tasks 14-23

As tasks **01-07 foram implementadas** (2026-09-15/16) e passaram por uma auditoria linha a linha
em 2026-09-16, com verificação empírica no Docker local (contagem de queries por notificação
`sql.active_record`, `to_sql` do finder, comparação `preloaded_label_list` × `label_list`,
`swagger:build`, RSpec e Vitest).

O que ficou **comprovadamente certo**: task 01 (`/pipelines` com 25 pipelines / 86 stages passou a
fazer 3 queries e **zero** carregando linhas de `pipeline_items`; os 8 pontos que renderizam
`_pipeline_stage` passam `items_counts`), task 02 (**zero** queries durante a serialização de 20
cards, e `preloaded_label_list` idêntico a `label_list` em todos eles), task 04 (`swagger:build`
sem diff, `$ref` do `show` preservado) e task 07 (os dois consumidores corrigidos, escopo da macro
agora server-side e visível no rótulo). 27 specs Vitest e 6 RSpec passando.

Um risco que a visão geral original levantava **não se confirmou**: `tagged_with(any: true)` no
acts-as-taggable-on 12 gera `EXISTS (...)`, não JOIN — não duplica linha nem quebra o
`total_count` do Kaminari.

Os 10 defeitos abaixo saíram dessa auditoria. Todos foram confirmados lendo o arquivo citado, e os
dois críticos também no banco/SQL real.

| # | Task | Severidade | Área | Depende de |
|---|------|------------|------|------------|
| [14](14-fix-ordenacao-sem-desempate.md) | Paginação sem desempate repete e pula cards entre páginas | 🔴 Crítico | Backend/Pipeline | — |
| [15](15-fix-arrastar-reordenar-volta-pro-lugar.md) | Arrastar para reordenar ainda volta pro lugar | 🔴 Crítico | Frontend/Pipeline | — (⚠️ decisão: fazer a 08 ou paliativo) |
| [16](16-fix-opcao-ordem-manual-no-menu.md) | Sem opção "ordem manual" no menu — arrasto fica desativado pra sempre | 🟠 Alta | Frontend/Pipeline | 15 |
| [17](17-fix-only-mine-e-assignee-id-divergem.md) | `only_mine` + `assignee_id` divergem entre servidor e cliente | 🟠 Alta | Backend+Frontend/Pipeline | — (⚠️ decisão de produto) |
| [18](18-fix-contador-coluna-dessincroniza-tempo-real.md) | Contador da coluna infla e conta em dobro no tempo real | 🟠 Alta | Frontend/Pipeline | — |
| [19](19-fix-macro-coluna-carrega-tudo-em-memoria.md) | Macro na coluna carrega todos os cards em memória | 🟡 Média | Backend/Pipeline | — |
| [20](20-fix-filtro-valor-exclui-value-null.md) | Filtro de valor exclui cards com `value` NULL | 🟡 Média | Backend+Frontend/Pipeline | — (⚠️ decisão de produto) |
| [21](21-fix-resetboard-sem-tratamento-de-erro.md) | Falha ao carregar uma coluna quebra o board em silêncio | 🟡 Média | Frontend/Pipeline | — |
| [22](22-fix-crlf-em-arquivos-ruby.md) | Dois arquivos Ruby salvos com CRLF (lint novo) | 🟢 Baixa | Backend/Lint | — |
| [23](23-fix-edit-pipeline-dispara-resetboard.md) | Salvar config do pipeline refaz o fetch de todas as colunas | 🟢 Baixa | Frontend/Pipeline | — |

**Prioridade:** 14, 16 e 17 antes de subir pra produção — são os três que dão **resultado errado
em silêncio** (card duplicado/sumido, arrasto travado sem saída, filtro combinado devolvendo o
conjunto errado). A 15 some sozinha quando a task 08 for feita; se a 08 não vier agora, o arrasto
fica visivelmente quebrado e o paliativo da 15 é obrigatório. A 18 e a 21 degradam a confiança no
board ao longo da sessão. 19, 20, 22 e 23 podem ir em qualquer ordem.

**Tasks que exigem decisão de produto antes de codar:** 15 (qual dos dois caminhos), 16 (o que
fazer com a preferência de ordenação já salva dos agentes), 17 (AND ou exclusivo) e 20 (NULL como
zero ou excluído).

## Segunda rodada de correções — tasks 24-31

As tasks **01-23 foram implementadas** e passaram por uma segunda auditoria em 2026-09-18, com o
mesmo método: leitura linha a linha + verificação empírica no Docker local.

### O que a auditoria confirmou funcionando

As 10 correções da leva 14-23 estão certas, e as tasks 08, 09, 10, 12 e 13 (que estavam
pendentes do plano original) também foram entregues. Evidências medidas, não inferidas:

- **14**: `ORDER BY pipeline_items.position asc, pipeline_items.id asc` nos dois ramos do
  `apply_sort`. Com `PIPELINE_ITEMS_RESULTS_PER_PAGE=1` numa stage com positions empatadas, as
  páginas voltaram **disjuntas e completas nos 4 modos de ordenação**.
- **15**: resolvida pela saída 1 (task 08) — `getFilteredSortedItemsForStage` e `compareByField`
  removidos, `KanbanColumn` consome `getItemsForStage` direto.
- **17**: SQL confirmado — `assignee_id = <eu> AND assignee_id = <outro>`, AND de verdade.
- **20**: `COALESCE(pipeline_items.value, 0) >= / <=`, com os 3 ramos preservados.
- **16/21/26-i18n**: `KANBAN.SORT.OPTIONS.MANUAL`, `KANBAN.COLUMN.ERROR` e `KANBAN.COLUMN.RETRY`
  presentes em `en/kanban.json` **e** `pt_BR/kanban.json`.
- **18**: `unloadedCountedIds` + `SET_UNLOADED_ITEM_COUNTED` resolvem tanto a inflação por update
  repetido quanto a corrida POST/WS — desenho sólido.
- **19**: `find_each(batch_size: 100)`, sem `blank?`; a medição do `includes` (303 vs 304 queries)
  foi bem feita e a conclusão está certa.
- **Suítes**: 59 RSpec e 23 Vitest passando, ESLint com **0 erros**, Swagger completo
  (`list-pipeline-board-items` com os 12 parâmetros + `start_position` no `reorder_payload`).

### Duas suspeitas que NÃO se confirmaram

Registradas para ninguém perder tempo perseguindo de novo:

1. **Task 12 não deixou admins de fora.** `ActionCableListener#user_tokens` já soma
   `account.administrators.pluck(:pubsub_token)` aos tokens dos membros — admins não-membros
   continuam recebendo os eventos, e há spec cobrindo (`spec/listeners/action_cable_listener_spec.rb`).
2. **Não houve renormalização em massa de line endings.** O `git status` inchado (centenas de
   `.js`/`.vue`) era cache de stat do git, não diff real — o diff são 62 arquivos. A regra
   `*.rb text eol=lf` do `.gitattributes` (task 22) é estreita e não tocou `.js`/`.vue`.

### Achados novos

| # | Task | Severidade | Área | Depende de |
|---|------|------------|------|------------|
| [24](24-fix-reorder-posicoes-cards-nao-carregados.md) | Reordenar a página 1 joga os cards não carregados para o topo | 🟠 Alta | Backend+Frontend/Pipeline | — (⚠️ decisão de produto) |
| [25](25-fix-poda-memoria-set-active-pipeline-noop.md) | A poda de memória da task 10 não descarta nada | 🟠 Alta | Frontend/Pipeline | — |
| [26](26-fix-i18n-alertas-reset-board.md) | Alertas de falha do board em inglês hardcoded | 🟡 Média | Frontend/i18n | — |
| [27](27-fix-unloaded-counted-ids-orfao-stage-origem.md) | `unloadedCountedIds` fica órfão na stage de origem | 🟢 Baixa | Frontend/Pipeline | — |
| [28](28-fix-ordem-insercao-destoa-ordem-manual.md) | Card inserido no cliente muda de lugar no refetch | 🟢 Baixa | Frontend/Pipeline | 24 |
| [29](29-fix-crlf-reincidente-pipeline-stages-controller.md) | `pipeline_stages_controller.rb` voltou para CRLF | 🟢 Baixa | Backend/Lint | — |
| [30](30-fix-inject-sem-default-kanban-card.md) | `inject` sem default em `KanbanCard.vue` | 🟢 Baixa | Frontend/Pipeline | — |
| [31](31-registrar-resultado-tasks-14-15-16.md) | Registrar o resultado das tasks 14, 15 e 16 | 🟢 Baixa | Documentação | — |

**Prioridade:** só a **24** é encontrável no uso normal — coluna grande + ordem manual (o padrão)
+ arrastar um card faz cards não tocados pularem para o topo no próximo carregamento. É a
"Observação relacionada" da task 14 chegando, e exige decisão de produto (atribuir `position` na
criação, com backfill do legado, ou normalizar a stage no `reorder`). A **25** não quebra nada,
mas o vazamento de memória que a task 10 dizia ter resolvido continua aberto — e o comentário no
código afirma o contrário, o que é o pior dos dois. As demais são acabamento.

**Executar a 24 antes da 28** — se os cards passarem a nascer com `position` própria, metade da 28
deixa de existir.

## ⚠️ Riscos consolidados (detalhe em cada task)

1. **`reorder` corrompe a ordem dos cards não carregados** (task 03). `reorder`
   (`pipeline_items_controller.rb:56-72`) reindexa `position` de `0..n` a partir de
   `ordered_ids`. Com paginação o frontend só conhece a página carregada, então reindexar de 0
   faz as posições colidirem com as dos cards das páginas seguintes. A action precisa aceitar
   um `start_position`. Risco alto e silencioso — sem isso a ordem do board embaralha em
   produção.
2. **Drag-and-drop entre colunas paginadas** (tasks 03 e 06). O `position` enviado hoje é o
   índice visual (`KanbanColumn.vue:42`); com páginas ele vira índice *dentro da página*. Como
   as páginas são prefixos contíguos ordenados por `position`, basta somar o offset — mas
   soltar "no fim da lista carregada" deixa de significar "no fim da coluna".
3. **ActionCable vira fonte de inconsistência** (task 05). `applyRealtimePipelineItem`
   (`actions.js:253-269`) faz `SET_ITEM`, que anexa o id ao fim de `itemOrder`
   (`mutations.js:108-115`). Com paginação, um card da página 5 apareceria no fim da página 1 e
   o contador ficaria dessincronizado.
4. **Divergência de resultado ao mover filtro pro servidor** (tasks 03 e 06). São 6 filtros
   (`constants.js:1-7` + `showOnlyMine`), incluindo o valor especial `'unassigned'` e
   `labelTitles` com semântica OR (`.some()` em `getters.js:91-93` → `tagged_with(any: true)`
   no backend). Qualquer diferença muda silenciosamente o que o agente vê.
5. **Consumidores que assumem "tudo carregado" quebram** (task 07):
   `PipelineStagesSection.vue:45` e o escopo do `KanbanRunMacroMenu` na coluna
   (`KanbanColumn.vue:86`).
6. **Mudança de contrato da API** (tasks 03 e 04). O `index` hoje devolve array puro e é
   compartilhado pelo board (`render :index`, linha 85) e pelo caminho "flat" de
   `ContactOpportunities.vue`/`ConversationOpportunities.vue`. Só o caminho do board ganha o
   envelope. Cuidado extra: `swagger/paths/index.yml:592` referencia o mesmo
   `items/index.yml` para o `show` de um item.
7. **Broadcast para a conta inteira** (task 12). `action_cable_listener.rb:180,187` publica
   todo `pipeline_item.created/updated` no `account_token`; todo usuário da conta recebe evento
   de todo pipeline, inclusive dos que não tem acesso (`PipelinePolicy::Scope` restringe via
   `user.assigned_pipelines`, o broadcast não). É custo de rede em escala **e** vazamento de
   dados entre pipelines.
8. **Sem cobertura de teste no `index`.** `spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb`
   cobre só `create` e `export`. Nenhuma dessas mudanças vai quebrar spec — o que significa que
   a validação tem que ser manual no Docker local, com volume real semeado.
9. **`enterprise/`**: `find enterprise -iname "*pipeline*"` não retorna nada hoje — nenhuma
   task aqui deve precisar de sincronização. Reconfirmar por task (skill
   `sincronizar-enterprise`) antes de fechar, não assumir.

## Padrões existentes que estas tasks devem seguir (não reinventar)

| Precisa de | Reusar de |
|---|---|
| Contagem agregada em 1 query, passada ao jbuilder | `PipelineItemsController#overdue_tasks_counts_for` (`pipeline_items_controller.rb:88-93`) — mesmo arquivo, mesmo padrão |
| Envelope de resposta paginada | `app/views/api/v1/accounts/contacts/index.json.jbuilder` → `{ meta: { count, current_page }, payload: [...] }` |
| `page`/`per` + `set_current_page` (Kaminari) | `contacts_controller.rb:12,129,133-142` |
| Per-page configurável por ENV | `conversation_finder.rb:215` (`CONVERSATION_RESULTS_PER_PAGE`) |
| Eager load de avatar e taggings | `conversation_finder.rb:202`, `contacts_controller.rb:135` |
| Scroll infinito | `IntersectionObserver.vue` + `ConversationList.vue:86-92` |
| Virtualização | `Virtualizer` de `virtua/vue`, já usado em `ConversationList.vue:69` |
| Batch update pré-carregado com `index_by(&:id)` | `pipeline_stages_controller.rb:30-44` |
| Índice parcial para cron | `index_tasks_on_due_date_pending_reminder` (`db/schema.rb:1331`) |

## Verificação geral

Semear alguns milhares de cards num pipeline no Docker local **antes** de medir qualquer
coisa — o problema não reproduz com dados de seed normais. Ligar o log de query do Rails e
comparar contagem de queries antes/depois em toda task de backend; o critério é sempre
"número de queries constante, não proporcional ao número de cards ou stages".

Regra do `AGENTS.md`: **não escrever specs a menos que pedido explicitamente**. A validação
destas tasks é manual.
