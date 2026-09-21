# Task 12 — Broadcast de pipeline item vai para a conta inteira

Severidade: 🟠 Alta. Achado na análise de performance de 2026-09-15.
Independente das demais.

## Objetivo

`app/listeners/action_cable_listener.rb:176-188`:

```ruby
def pipeline_item_created(event)
  pipeline_item = event.data[:pipeline_item]
  account = pipeline_item.account
  broadcast(account, [account_token(account)], PIPELINE_ITEM_CREATED, pipeline_item.push_event_data)
end

def pipeline_item_updated(event)
  pipeline_item = event.data[:pipeline_item]
  account = pipeline_item.account
  broadcast(account, [account_token(account)], PIPELINE_ITEM_UPDATED, pipeline_item.push_event_data)
end
```

Todo evento de card vai para o `account_token`, ou seja, para **todo usuário logado da conta** —
`RoomChannel` faz `stream_from "account_#{id}"` para usuários autenticados.

São dois problemas distintos:

**Escala.** Com uma conta movimentada, cada movimentação de card vira uma mensagem para todas
as sessões abertas, e cada cliente executa `applyRealtimePipelineItem` (`actions.js:253-269`).
Hoje o guard dele é `if (state.activePipelineId !== item.pipeline_id) return` — ou seja, o
cliente recebe, desserializa e descarta. Em volume, é tráfego e CPU desperdiçados em toda
sessão aberta, e uma automação ou macro em lote multiplica isso por card afetado.

**Vazamento de dados.** `PipelinePolicy::Scope` restringe pipelines a `user.assigned_pipelines`
(`app/policies/pipeline_policy.rb:3-6`, `app/models/user.rb:142-144`), mas o broadcast não
respeita isso. O payload de `push_event_data` (`app/models/pipeline_item.rb:95-115`) inclui
nome, e-mail, telefone e avatar do contato, valor da oportunidade, notas, responsável e
etiquetas. Um agente sem acesso ao pipeline recebe tudo isso pelo WebSocket — não aparece na
UI, mas está no tráfego da sessão dele.

Isso não é regressão de nenhuma task anterior: o listener nasceu assim
(`claude/pipeline_tasks/10-kanban-atualizacao-tempo-real.md`), quando o volume não expunha
nenhum dos dois problemas.

## O que corrigir

1. Resolver os destinatários por pipeline em vez de por conta: os membros do pipeline
   (`Pipeline#members`, via `pipeline_members`) mais os administradores da conta — que é
   exatamente o critério de `User#assigned_pipelines`. O `ActionCableListener` já faz esse tipo
   de cálculo de destinatários para os eventos de conversa (resolve os `pubsub_token`s dos
   agentes/admins do inbox); seguir o mesmo formato, não inventar um novo.
2. Atenção ao custo da própria resolução: não pode virar uma query por evento por usuário —
   com automação em lote, o listener roda por card. Se a resolução ficar cara, considerar
   cachear os tokens por pipeline dentro do processamento do lote.
3. Verificar se o guard de `applyRealtimePipelineItem` (`actions.js:254`) ainda é necessário
   depois disso. Provavelmente sim (o agente pode ser membro de vários pipelines e ter só um
   aberto) — **não remover** sem confirmar.
4. `.rubocop.yml` já tem `app/listeners/action_cable_listener.rb` no exclude de
   `Metrics/ClassLength` — não é desculpa para crescer o arquivo sem necessidade; se a lógica
   de destinatários ficar grande, extrair.

## Testes

Docker local, três usuários: um admin, um agente membro do pipeline A, e um agente que **não**
é membro de nenhum pipeline.

1. Com as três sessões abertas (DevTools → Network → WS em cada uma), mover um card no
   pipeline A e inspecionar os frames recebidos: admin e membro recebem; o não-membro **não**
   recebe nada.
2. Board do membro continua atualizando em tempo real: mover/criar/apagar card numa sessão
   reflete na outra (os três eventos, não só o de movimentação).
3. Rodar uma macro em lote numa coluna e confirmar que o board atualiza — é o caminho que
   `KanbanRunMacroMenu.vue:64-72` depende exclusivamente do broadcast, sem refetch.
4. Log de query durante a macro em lote: a resolução de destinatários não pode gerar uma query
   por card por usuário.

## Critério de pronto

- Evento de pipeline item chega só a quem tem acesso ao pipeline (membros + admins).
- Tempo real do board inalterado para quem tem acesso, nos 3 eventos.
- Resolução de destinatários não introduz N+1 no caminho de lote.
- Nenhuma extensão correspondente em `enterprise/` (confirmar com a skill
  `sincronizar-enterprise`).
- `bundle exec rubocop -a` limpo.
