# Task 09 — Automação: gatilhos nativos do pipeline

Parte do Grupo D ([visão geral](00-visao-geral.md)). Depende da task 04 (as mesmas ações de
pipeline já existem, só ganham novos eventos capazes de dispará-las). Incluída no escopo por
decisão explícita do cliente (automação deve poder disparar a partir de mudanças no próprio
pipeline, não só a partir de eventos de conversa).

## Objetivo

Permitir regras do tipo "quando um card entra no estágio Ganho → fazer X", disparadas por
mudanças no próprio `PipelineItem`, não por eventos de conversa.

## Por que isso é mais simples do que parece — reaproveitar mecanismo já existente

O guard anti-loop de automação (`AutomationRuleListener#performed_by_automation?`, em
`app/listeners/automation_rule_listener.rb`) verifica apenas
`event.data[:performed_by].instance_of?(AutomationRule)`. Esse dado já é propagado
automaticamente hoje: `AutomationRules::ActionService#initialize` seta
`Current.executed_by = rule` (linha 6), e os métodos de disparo de evento em
`conversation.rb`/`message.rb` (`dispatcher_dispatch`) já enviam `performed_by:
Current.executed_by` a cada `Rails.configuration.dispatcher.dispatch(...)`. **Ou seja: o
guard já funciona de graça para qualquer evento novo, desde que `PipelineItem` propague
`performed_by` do mesmo jeito.** Não é preciso inventar um mecanismo novo de anti-loop — só
replicar o padrão.

## 1. Novos eventos em `lib/events/types.rb`

Módulo simples de constantes string, puramente aditivo:
```ruby
PIPELINE_ITEM_CREATED = 'pipeline_item.created'
PIPELINE_ITEM_STAGE_CHANGED = 'pipeline_item.stage_changed'
```
Começar só com esses dois (cobrem "card criado" e "card mudou de estágio", que cobre o
exemplo "entrou em Ganho" — `won` é só mais um `stage_type` de estágio). Avaliar
`PIPELINE_ITEM_UPDATED` (mudança de valor/título/notas) como extensão futura, só se pedido.

## 2. Disparo em `app/models/pipeline_item.rb`

Callbacks mirror exato do padrão já usado em `conversation.rb`/`message.rb`:
```ruby
after_create :dispatch_created_event
after_update :dispatch_stage_changed_event, if: :saved_change_to_pipeline_stage_id?

private

def dispatch_created_event
  Rails.configuration.dispatcher.dispatch(
    Events::Types::PIPELINE_ITEM_CREATED, Time.zone.now,
    pipeline_item: self, performed_by: Current.executed_by
  )
end

def dispatch_stage_changed_event
  Rails.configuration.dispatcher.dispatch(
    Events::Types::PIPELINE_ITEM_STAGE_CHANGED, Time.zone.now,
    pipeline_item: self, performed_by: Current.executed_by,
    previous_stage_id: saved_change_to_pipeline_stage_id.first
  )
end
```

## 3. Listener

`app/listeners/automation_rule_listener.rb` — adicionar métodos novos, mesmo formato de
`process_conversation_event`:
```ruby
def pipeline_item_created(event)
  process_pipeline_item_event(event, 'pipeline_item_created')
end

def pipeline_item_stage_changed(event)
  process_pipeline_item_event(event, 'pipeline_item_stage_changed')
end

private

def process_pipeline_item_event(event, event_name)
  return if performed_by_automation?(event)

  pipeline_item = event.data[:pipeline_item]
  account = pipeline_item.account
  rules = current_account_rules(event_name, account)
  rules.each do |rule|
    conditions_match = ::AutomationRules::PipelineConditionsFilterService.new(rule, pipeline_item).perform
    ::AutomationRules::PipelineActionService.new(rule, account, pipeline_item).perform if conditions_match.present?
  end
end
```

Não é necessária mudança em `AsyncDispatcher#listeners` — a mesma instância de
`AutomationRuleListener` já registrada passa a responder aos novos métodos.

**Serviço de ação para estes eventos**: como o card já existe (é o próprio sujeito do
evento), não faz sentido resolver via `@conversation.contact` como na task 04 — criar
`AutomationRules::PipelineActionService` (paralelo a `AutomationRules::ActionService`),
incluindo o módulo compartilhado `PipelineItemActions` da task 06 e chamando os métodos
diretamente com `pipeline_item` (sem a etapa de resolução por conversa). Ações disponíveis
aqui: as mesmas 7 de `PIPELINE_ACTIONS_ATTRS` (sem `create_pipeline_item` — o card que
disparou o evento já existe).

## 4. Condições baseadas em estado do pipeline

Hoje `AutomationRules::ConditionsFilterService` é 100% construído sobre
`Conversation.where(id: @conversation.id)` — não serve para condições como "estágio = Ganho
E valor > X". Criar:
- Nova classe `AutomationRules::PipelineConditionsFilterService`, com `base_relation`
  começando em `PipelineItem` em vez de `Conversation` — mirror da estrutura da classe
  existente, adaptando os joins.
- Novo bloco `pipeline_items:` em `lib/filters/filter_keys.yml` (mirror dos blocos
  `conversations:`/`contacts:`/`messages:` já existentes), com atributos: `stage_id`,
  `pipeline_id`, `value`, `assignee_id`, `team_id`, `labels`.
- Extensão equivalente em `AutomationRules::ConditionValidationService` para validar contra
  o novo bloco.

## 5. Whitelist de conditions/actions

A UI (`constants.js`, task 05) já decide quais condições/ações aparecem por `event_name` — o
backend só precisa que `ConditionValidationService` valide contra o bloco certo do YAML
dependendo do evento da regra. As ações disponíveis para estes 2 eventos novos são as mesmas
7 já listadas em `AutomationRule#actions_attributes` (task 04) — não precisa de uma lista
separada.

## Testes

- `spec/listeners/automation_rule_listener_spec.rb` (estender se existir, criar se não) —
  regras nos 2 eventos novos disparam corretamente; **teste explícito de ciclo**: regra A
  (dispara em `pipeline_item_created`) move o card para o estágio que regra B monitora, regra
  B (dispara em `pipeline_item_stage_changed`) tenta mover de volta para o estágio inicial —
  confirmar que o guard `performed_by_automation?` interrompe o ciclo na segunda iteração
  (não em loop infinito).
- `spec/services/automation_rules/pipeline_conditions_filter_service_spec.rb` — condições de
  estágio/valor/label.
- `spec/services/automation_rules/pipeline_action_service_spec.rb` — mesmas ações da task 04,
  agora chamadas diretamente sobre o `pipeline_item` sem resolução via conversa.

## Critério de pronto

- 2 novos eventos disparando regras corretamente, com condições de pipeline funcionando.
- Teste de ciclo de 2 regras confirmando que o guard anti-loop existente funciona sem
  modificação nenhuma nele.
