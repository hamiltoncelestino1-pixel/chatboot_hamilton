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
