# Task 18 — Diagnóstico ao vivo: atualização em tempo real do Kanban não funciona

Task de diagnóstico pós-implementação da task 10. Achado na auditoria de 2026-08-01. **Esta task
não é uma correção de código** — é um roteiro guiado para achar, ao vivo, o ponto exato onde a
cadeia quebra, já que a revisão estática do código não encontrou nenhum defeito de lógica.

## Objetivo

O usuário reportou que a atualização em tempo real dos cards do Kanban não funciona — nem para
movimentação manual nem quando uma macro/automação move ou cria um card em background. A
auditoria traçou manualmente toda a cadeia (model → dispatcher → listener → canal ActionCable →
frontend → Vuex → componente) e **confirmou, por leitura direta do código**, que cada elo está
correto:

- `app/models/pipeline_item.rb` dispara `PIPELINE_ITEM_CREATED`/`PIPELINE_ITEM_UPDATED` nas
  condições certas (`broadcast_relevant_change?` cobre `pipeline_stage_id`/`assignee_id`/`team_id`).
- `app/listeners/action_cable_listener.rb#pipeline_item_created/updated` faz broadcast pro canal
  `"account_#{account.id}"` — o mesmo já usado por `contact_created`/`contact_updated` em produção.
- `app/channels/room_channel.rb#ensure_stream` já abre esse stream para qualquer `User` logado,
  incondicionalmente (não depende da página do Kanban estar aberta).
- `app/javascript/dashboard/helper/actionCable.js` escuta exatamente essas duas strings de evento
  e despacha `kanban/applyRealtimePipelineItem`.
- Essa action usa as mutations já existentes (`MOVE_ITEM`/`SET_ITEM`) sobre o state reativo do
  Vuex; o board (`KanbanColumn.vue`) lê via `computed` + `watch`, padrão reativo correto em
  Vue 3/Vuex 4.
- Nenhum caminho de automação/macro/export usa `update_column`/`update_all` (que bypassaria os
  callbacks `after_update` e quebraria o disparo do evento).
- O guard anti-loop de automação (`performed_by_automation?`) não interfere no broadcast — o
  `ActionCableListener` nunca checa `performed_by`.

Ou seja: pelo código, tanto o cenário "usuário move card manualmente" (numa segunda sessão
observando) quanto "automação/macro move card em background" deveriam propagar corretamente.
Isso não prova ausência de bug — só que a causa mais provável está fora do alcance de uma leitura
estática (ambiente/processo, ou um detalhe só visível em runtime).

## Contexto adicional levantado (não conclusivo, mas relevante para o diagnóstico)

- O broadcast real (`ActionCableBroadcastJob`) é **assíncrono** — processado pelo Sidekiq, não
  importa se o evento partiu de um request HTTP ou de um Job em background. Se o processo Sidekiq
  estiver com código desatualizado (não recarregado após as mudanças em `pipeline_item.rb`/
  `action_cable_listener.rb`), o broadcast simplesmente não sai.
- O movimento manual de card via drag-and-drop (`kanban/moveItem`,
  `app/javascript/dashboard/store/modules/kanban/actions.js`) é um **update otimista local** — a
  aba que faz o drag sempre "funciona" independente de ActionCable, porque atualiza o Vuex antes
  mesmo da resposta da API chegar. Isso é preexistente, não depende desta task. **O teste válido
  de tempo real é sempre com uma segunda sessão/aba que não fez a ação.**
- No ambiente Docker local, `rails`/`vite` recarregam automaticamente em desenvolvimento, mas o
  container `sidekiq` roda um processo Ruby de longa duração — dependendo de como o worker está
  configurado, ele pode não recarregar constantes já carregadas em memória sem um restart
  explícito do container.

## Roteiro de diagnóstico (executar nesta ordem, parando no primeiro passo que falhar)

1. **Ambiente limpo.** Reiniciar o container `sidekiq` (`docker compose restart sidekiq`) e
   confirmar no Vite/console do navegador que o bundle do frontend está servindo a versão mais
   recente de `actionCable.js` (hard refresh / limpar cache se necessário).
2. **Baseline: o tempo real já existente funciona?** Abrir duas abas logadas com usuários/sessões
   diferentes numa mesma conversa; em uma aba, enviar uma mensagem; confirmar que a outra aba
   recebe em tempo real (evento `message.created`, pré-existente, não tocado por este épico). Se
   isso **também** não funcionar, o problema é ambiental/de infraestrutura (Redis, ActionCable,
   Sidekiq) e não específico do Kanban — pare aqui e resolva isso primeiro.
3. **Cenário (a) — card movido manualmente, observado numa segunda sessão.** Abrir o mesmo board
   do Kanban em duas abas/sessões (usuários diferentes com acesso ao mesmo pipeline). Mover um
   card na aba 1. Verificar, nesta ordem:
   - No log do Sidekiq (`docker compose logs -f sidekiq`), aparece o processamento de
     `ActionCableBroadcastJob` logo após o `update!` do card?
   - No devtools do navegador da aba 2 (aba Network → WS), o frame do WebSocket chega com
     `event: "pipeline_item.updated"` e o payload esperado (`pipeline_id`, `pipeline_stage_id`
     corretos)?
   - Se o frame chega mas a aba 2 não atualiza visualmente: o problema é no frontend
     (`actionCable.js` → `kanban/applyRealtimePipelineItem` → reatividade do componente) — inspecionar
     o Vuex devtools da aba 2 para ver se `state.kanban.items`/`itemOrder` de fato mudou.
   - Se o frame **não** chega: o problema é no backend (dispatcher → listener → broadcast) —
     confirmar no log do Rails/Sidekiq se `pipeline_item_updated`/`pipeline_item_created` foi
     sequer chamado.
4. **Cenário (b) — automação nativa (task 09) move o card em background.** Configurar uma regra
   simples (ex. "card criado → mover para estágio X") e criar um card que dispare a regra.
   Repetir as mesmas verificações do passo 3 (log do Sidekiq, frame WS, Vuex devtools) para essa
   automação especificamente.
5. **Cenário (c) — macro de pipeline (task 06/07) roda via job.** Rodar uma macro de pipeline em
   um card a partir do Kanban. Repetir as mesmas verificações.

## O que fazer com o resultado

- Se o passo 2 (baseline) falhar: não é escopo desta task — é um problema de infraestrutura mais
  amplo (Redis/ActionCable/Sidekiq), documentar e escalar separadamente.
- Se algum dos passos 3/4/5 apontar exatamente onde a cadeia quebra (ex. "o job nunca é
  enfileirado", "o frame WS nunca chega", "chega mas o Vuex não atualiza"): abrir uma nova task de
  correção específica para esse ponto exato, com a evidência coletada aqui (logs, payload do
  frame WS, estado do Vuex) — não tentar adivinhar a causa sem essa evidência.
- Se todos os passos passarem (ou seja, o tempo real na verdade já funciona depois do restart
  limpo do ambiente): documentar que a causa original era o processo Sidekiq com código
  desatualizado (ou bundle de frontend desatualizado), e não é necessária nenhuma mudança de
  código — só o processo de deploy/reload local precisa ser lembrado (ex. adicionar uma nota em
  `claude/08-ambiente-local-docker.md` sobre reiniciar o Sidekiq após mudanças em listeners/models
  que afetam jobs em background).

## Critério de pronto

- Roteiro executado até o fim (ou até achar o ponto exato de quebra).
- Causa raiz identificada com evidência concreta (log/payload/estado), não suposição.
- Se uma correção de código for necessária, uma nova task numerada (19+) é aberta especificamente
  para ela, com o achado desta investigação como base.
- Se a causa for só ambiental, `claude/08-ambiente-local-docker.md` atualizado com a lição
  aprendida (gotcha novo), e nenhuma mudança de código necessária.

## Resultado do diagnóstico (2026-08-03)

Causa raiz encontrada e corrigida direto nesta sessão (sem abrir task 19 separada — o achado surgiu
de QA ao vivo da task 16, não do roteiro acima executado à parte, mas cobre exatamente o sintoma
que esta task descreve). Dois bugs distintos, o segundo só ficou visível depois do primeiro corrigido.

### Causa raiz 1 — broadcast de `pipeline_item` derrubava a própria gravação

`app/models/pipeline_item.rb` disparava o dispatch do evento em `after_create`/`after_update`
(dentro da transação), não em `after_create_commit`/`after_update_commit` como `Conversation`/
`Contact` já faziam. `push_event_data` devolvia `value:` como `BigDecimal` cru (coluna
`decimal(15,2)`, inclusive no default `0.0`) — o Sidekiq deste projeto roda em modo `strict_args`
(padrão desde a v7) e rejeita `BigDecimal` como argumento de job, então
`ActionCableBroadcastJob.perform_later(...)` sempre lançava `ArgumentError` ao tentar enfileirar o
broadcast de **qualquer** card criado/atualizado. Como o dispatch rodava dentro da transação
(`after_create`, não `_commit`), essa exceção **revertia a gravação inteira** — o card nunca era
persistido, não só o broadcast falhava.

Reproduzido ao vivo via `rails runner` chamando a action exata de uma automation rule: antes do
fix, `ArgumentError` + `PipelineItem.count == 0`; depois do fix, card criado normalmente.

**Corrigido em:**
- `app/models/pipeline_item.rb` — `after_create`/`after_update` → `after_create_commit`/
  `after_update_commit`; `push_event_data` usa `value: json_safe_value` (`value&.to_f`) em vez de
  `value: value`.

Isso resolve tanto "automação/macro não cria ou move o card" (o card nunca era salvo) quanto "o
Kanban não atualiza em tempo real" (o broadcast, quando chegava a rodar, também falhava) — as duas
faces do mesmo bug.

### Causa raiz 2 — corrida entre refetch manual e o tempo real (só apareceu depois da causa 1 corrigida)

Com o tempo real já funcionando, surgiu um segundo sintoma: rodar uma macro em **todos os cards de
uma etapa** (botão no cabeçalho da coluna, `KanbanColumn.vue` → `KanbanRunMacroMenu.vue`, mesmo
componente usado no card individual) só movia visualmente o **último** card processado — os demais
ficavam presos na coluna antiga, embora o backend tivesse movido todos (confirmado atualizando a
página).

`KanbanRunMacroMenu.vue#runMacro` despachava `kanban/fetchItems` (REST) logo depois de
`macros/execute` resolver — mas `macros/execute` só enfileira o `MacrosPipelineExecutionJob`, não
espera ele terminar. Esse refetch buscava uma foto do board **antes** do job mover os cards,
competindo com os broadcasts em tempo real (um por card). Como a mutation `SET_ITEMS`
(`store/modules/kanban/mutations.js`) só adiciona um id na ordem da coluna nova sem remover da
antiga, o card cujo update em tempo real "perdia" a corrida contra a foto desatualizada ficava
duplicado entre as duas colunas, visualmente preso na antiga. Com 1 card só, o WebSocket quase
sempre ganhava a corrida — por isso parecia funcionar sempre no card individual.

**Corrigido em:**
- `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanRunMacroMenu.vue` — removida
  a chamada `kanban/fetchItems` de dentro do `runMacro()`; o board se atualiza só via WebSocket
  (mesmo padrão já usado pelo drag-and-drop manual, que nunca fez refetch).

### Lição para `claude/08-ambiente-local-docker.md`

Ainda vale reiniciar `sidekiq` depois de mudar `app/models/*.rb`/`app/listeners/*.rb` em dev (o
worker não recarrega sozinho) — mas neste caso específico a causa raiz era um bug de código, não
só um processo desatualizado.
