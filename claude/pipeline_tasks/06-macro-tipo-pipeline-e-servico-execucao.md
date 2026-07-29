# Task 06 — Macros: `macro_type` + serviço de execução em pipeline

Parte do Grupo C ([visão geral](00-visao-geral.md)). Depende das tasks 01 (validação de card
único, herdada nas ações que criam/movem cards) e conceitualmente reaproveita o desenho da
task 04 (mesmas ações de mutação, agora expostas também como macro).

## Objetivo

Permitir criar macros que atuam sobre um `PipelineItem` (card) em vez de uma `Conversation`,
executáveis a partir do Kanban (UI na task 08).

## 1. Nova coluna `macro_type` em `Macro`

Migration `db/migrate/<timestamp>_add_macro_type_to_macros.rb`:
```ruby
add_column :macros, :macro_type, :integer, default: 0, null: false
```
(`0 = conversation`, `1 = pipeline_item`).

**Por que uma coluna nova em vez de inferir pelo nome da ação**: uma macro rodando sobre um
card não tem `@conversation` disponível, então misturar ações de conversa e de pipeline numa
mesma macro não faz sentido — seria ambíguo. Uma coluna explícita também permite ao frontend
(task 08) filtrar quais macros aparecem no Kanban vs. na conversa sem precisar inspecionar o
conteúdo de `actions`.

## 2. `app/models/macro.rb`

- `enum macro_type: { conversation: 0, pipeline_item: 1 }`.
- Renomear a constante atual `ACTIONS_ATTRS` para `CONVERSATION_ACTIONS_ATTRS` (mesmo
  conteúdo de hoje, sem mudança).
- Nova constante `PIPELINE_ACTIONS_ATTRS`:
  ```ruby
  PIPELINE_ACTIONS_ATTRS = %w[move_pipeline_item_stage assign_pipeline_item_agent
                              assign_pipeline_item_team add_pipeline_item_label
                              remove_pipeline_item_label update_pipeline_item
                              export_pipeline_item].freeze
  ```
  **Sem `create_pipeline_item`** — uma macro roda sobre um card que já existe (é o alvo da
  execução), então "criar" não se aplica aqui, diferente da automação (task 04), onde o card
  ainda não existe quando a regra dispara.
- `json_actions_format` — escolher a lista certa (`CONVERSATION_ACTIONS_ATTRS` ou
  `PIPELINE_ACTIONS_ATTRS`) conforme `macro_type`, mantendo a mensagem de erro já existente.

## 3. Lógica de mutação compartilhada com a task 04 (evitar duplicar as mesmas 7 ações)

Extrair a lógica de campo (mover stage, atribuir agente/time, labels, update, export) para um
módulo novo, `app/services/concerns/pipeline_item_actions.rb`, com métodos que recebem o
`pipeline_item` explicitamente:

```ruby
module PipelineItemActions
  def move_stage(pipeline_item, params)
    # ...mesma lógica que hoje estaria em AutomationRules::ActionService#move_pipeline_item_stage
  end
  # assign_agent, assign_team, add_label, remove_label, update_fields, export
end
```

- Incluído em `AutomationRules::ActionService` (task 04) — lá, o método público
  `move_pipeline_item_stage(params)` resolve o item via
  `resolve_pipeline_item_for_conversation` e chama `move_stage(item, params)` do módulo.
- Incluído também no novo serviço de macro (item 4 abaixo), que já tem o item diretamente (não
  precisa resolver a partir de conversa).

Isso evita duas implementações divergentes da mesma regra de negócio entre automação e macro
— **se a task 04 já foi implementada primeiro, esta task deve refatorar aquele código para
usar o módulo compartilhado**, não duplicar.

## 4. `app/services/macros/pipeline_execution_service.rb` (novo)

**Não herda de `ActionService`** — essa classe-base é 100% acoplada a `@conversation`
(`app/services/action_service.rb`), o que não se aplica aqui. Classe própria:

```ruby
class Macros::PipelineExecutionService
  include PipelineItemActions

  def initialize(macro, pipeline_item, user)
    @macro = macro
    @pipeline_item = pipeline_item
    @account = macro.account
    @user = user
    Current.user = user
  end

  def perform
    @macro.actions.each do |action|
      action = action.with_indifferent_access
      begin
        send(action[:action_name], @pipeline_item, action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end
end
```

Mesmo formato de `Macros::ExecutionService#perform` já existente (rescue por ação, sem
crashar a macro inteira).

## Testes

- `spec/models/macro_spec.rb` (criar se não existir) — enum `macro_type`; `json_actions_format`
  valida contra `CONVERSATION_ACTIONS_ATTRS` quando `macro_type: conversation` e contra
  `PIPELINE_ACTIONS_ATTRS` quando `macro_type: pipeline_item`.
- `spec/services/concerns/pipeline_item_actions_spec.rb` — testar a lógica de negócio uma
  única vez aqui (reaproveitada pelos specs de automação da task 04 e de macro desta task, sem
  duplicar asserções).
- `spec/services/macros/pipeline_execution_service_spec.rb` — um exemplo por ação do
  `PIPELINE_ACTIONS_ATTRS`, incluindo rescue por-ação em caso de falha.

## Critério de pronto

- `macro_type` funcionando com a whitelist correta por tipo.
- Módulo `PipelineItemActions` compartilhado entre automação (task 04) e macro, sem lógica
  duplicada.
- `Macros::PipelineExecutionService` testado isoladamente (ainda sem job/controller/UI — isso
  é a task 07/08).
