---
name: fluxo-evento-wisper
description: Use ao adicionar ou modificar um evento de domínio neste projeto Rails (model → Dispatcher/Wisper → listener → job/ActionCable). Ativar quando o pedido envolver "disparar um evento novo", "reagir a X quando Y acontecer", "automação deve rodar quando...", "notificar via tempo real/ActionCable quando...", ou tocar em app/dispatchers/, app/listeners/, lib/events/types.rb, config/initializers/event_handlers.rb ou app/javascript/dashboard/helper/actionCable.js.
---

# Fluxo de evento (Wisper) neste projeto

Código completo de referência (todos os arquivos citados abaixo, verbatim):
[references/wisper-codigo.md](references/wisper-codigo.md)

## Passo a passo

1. **Nomear o evento** em `lib/events/types.rb` (módulo `Events::Types`). Convenção:
   `NOME_PASSADO = 'noun.past_tense'` (ex. `PIPELINE_ITEM_CREATED = 'pipeline_item.created'`,
   `lib/events/types.rb:64`). O `.` na string vira `_` no nome do método do listener
   (Wisper resolve isso via `event_object.method_name`).

2. **Disparar no model**: callback `after_create`/`after_update` — **não é sempre
   `_commit`**, confira o modelo real antes de assumir. `PipelineItem` usa
   `after_create :dispatch_created_event` e `after_update :dispatch_stage_changed_event, if:
   :saved_change_to_pipeline_stage_id?` (`app/models/pipeline_item.rb:63-65`), chamando:
   ```ruby
   Rails.configuration.dispatcher.dispatch(
     Events::Types::X, Time.zone.now,
     thing: self, performed_by: Current.executed_by
   )
   ```
   `performed_by: Current.executed_by` é **obrigatório** — é o campo que evita loop de
   automação (passo 5).

3. **Entender sync vs async** — `Dispatcher#dispatch` chama os dois incondicionalmente
   (`app/dispatchers/dispatcher.rb:15-18`):
   - **`SyncDispatcher`** (`app/dispatchers/sync_dispatcher.rb:7-9`) — roda inline no mesmo
     request/callback. Só tem `ActionCableListener.instance` e `AgentBotListener.instance`.
     Só coloque um listener aqui se for rápido e não bloqueante.
   - **`AsyncDispatcher`** (`app/dispatchers/async_dispatcher.rb:11-23`) — enfileira
     `EventDispatcherJob` (Sidekiq, `queue_as :critical`), que depois publica pros 9
     listeners assíncronos: `AutomationRuleListener`, `CampaignListener`,
     `CsatSurveyListener`, `HookListener`, `InstallationWebhookListener`,
     `NotificationListener`, `ParticipationListener`, `ReportingEventListener`,
     `WebhookListener`.

4. **Criar um listener novo** (se necessário): herdar `BaseListener` (já inclui `Singleton`,
   `app/listeners/base_listener.rb:2`), método nomeado igual ao evento com `.`→`_`
   (ex. `pipeline_item_stage_changed`, ver `automation_rule_listener.rb:41-43`). Adicionar
   `.instance` no array `listeners` do dispatcher certo (`sync_dispatcher.rb` ou
   `async_dispatcher.rb`) — **não precisa mexer em `config/initializers/event_handlers.rb`**,
   ele só chama `load_listeners` automaticamente no boot/reload.

5. **Guard contra loop de automação**: se o listener novo reage a algo que uma automação
   também poderia causar, replicar o guard usado em `AutomationRuleListener`:
   ```ruby
   def performed_by_automation?(event)
     event.data[:performed_by].present? && event.data[:performed_by].instance_of?(AutomationRule)
   end
   ```
   (`automation_rule_listener.rb:97-99`) e usar como early-return no início do processamento.

6. **Se precisa tempo real**: adicionar um método em `ActionCableListener`
   (`app/listeners/action_cable_listener.rb`) escolhendo o escopo de `pubsub_token` certo —
   três padrões confirmados no código (exemplos completos em
   [references/wisper-codigo.md](references/wisper-codigo.md)):
   - **Conta inteira**: `account_token(account)` → `"account_#{account.id}"`
     (linhas 192-194) — usado por `pipeline_item_created`/`pipeline_item_updated`
     (linhas 176-188). Todo usuário logado assina esse stream (ver `RoomChannel`).
   - **Agentes+admins de um inbox**: `user_tokens(account, agents)` (linhas 207-211).
   - **Por contato**: `contact_inbox_tokens`/`contact_tokens` (linhas 213-225).
   Depois chamar o método privado `broadcast(account, tokens, EVENT_CONSTANT, data)`
   (linhas 227-236), que enfileira `ActionCableBroadcastJob` (`queue_as :critical`).

7. **Ponto de atenção — sem codegen, checar sempre**: `lib/events/types.rb` (constantes do
   backend) e o mapa `events` em `app/javascript/dashboard/helper/actionCable.js:15-40`
   (chaves = string do evento, ex. `'pipeline_item.created'`) **não são sincronizados
   automaticamente**. Esquecer de adicionar a entrada no JS faz o evento nunca chegar no
   frontend, mesmo com o broadcast do backend funcionando 100%. Adicione o handler:
   ```js
   onThingChanged = data => {
     this.app.$store.dispatch('module/actionName', data);
   };
   ```
   e registre `'thing.created': this.onThingChanged` no mapa `events`.

## Checklist final — "esse evento novo está completo"

- [ ] Constante criada em `lib/events/types.rb`
- [ ] Model dispara o evento com `performed_by: Current.executed_by`
- [ ] Se precisa automação/webhook/etc: listener assíncrono criado/atualizado e registrado no
      array `listeners` do dispatcher certo
- [ ] Se precisa tempo real: método em `ActionCableListener` com o escopo de token correto
- [ ] Entrada correspondente adicionada no mapa `events` de `actionCable.js` (frontend)
- [ ] Se o evento reage a algo que automação também pode causar: guard
      `performed_by_automation?` replicado no listener novo
