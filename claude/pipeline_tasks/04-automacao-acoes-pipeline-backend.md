# Task 04 — Automation Rules: novas ações de pipeline (backend)

Parte do Grupo B ([visão geral](00-visao-geral.md)). Depende da task 01 (coluna `pipeline_id`
sincronizada em `PipelineItem`, usada para resolver "o card deste contato neste pipeline").

## Objetivo

Cobrir o exemplo citado pelo cliente — "nova conversa aberta → cria card no pipeline X /
estágio Y com o mesmo agente da conversa" — reaproveitando os eventos de automação que **já
existem** (`conversation_created`, `conversation_updated`, `conversation_opened`,
`conversation_resolved`, `message_created`). **Não mexe** em `AsyncDispatcher`,
`lib/events/types.rb` ou no listener nesta task — isso é escopo da task 09 (gatilhos nativos
do pipeline). Aqui só adicionamos **ações** novas aos eventos que já disparam automações.

## 1. Novos métodos em `app/services/automation_rules/action_service.rb`

Adicionar como métodos privados, seguindo o padrão já usado por `send_email_to_team` (que já
recebe um hash dentro do array `action_params`, não só escalares):

- `create_pipeline_item(params)` —
  `params = [{ pipeline_id:, pipeline_stage_id:, assignee_mode:, team_mode:, title:, value:, notes: }]`.
  - `assignee_mode`: `'conversation_assignee'` (usa `@conversation.assignee_id`),
    `'none'` (sem atribuição), ou um id de usuário explícito — mesma convenção solta já usada
    em `assign_agent` (`'last_responding_agent'`/`'nil'`).
  - Resolve `contact = @conversation.contact`; cria via
    `@account.pipeline_items.new(contact_id: contact.id, conversation_id: @conversation.id, pipeline_stage_id:, assignee_id: resolvido, team_id: resolvido, title:, value:, notes:).save!`.
  - Herda a validação de card único da task 01 automaticamente — se o contato já tiver card
    nesse pipeline, o `save!` levanta `ActiveRecord::RecordInvalid`, que já cai no
    `rescue StandardError` por-ação existente em `perform` (linha ~14-20 do arquivo) — a regra
    não crasha, só essa ação é pulada e reportada via `ChatwootExceptionTracker`.
- `move_pipeline_item_stage(params)` — `[{ pipeline_id:, target_stage_id: }]`. Usa o helper
  privado novo `resolve_pipeline_item_for_conversation(pipeline_id)` (ver item 2 abaixo);
  atualiza `pipeline_stage_id` e recalcula `position` (último da coluna de destino, mesmo
  critério de `Pipelines::ExportItemService#next_position`). Se não existir card do contato
  nesse pipeline, no-op silencioso com `Rails.logger.info` (não é erro — "mover" só faz
  sentido se já existe um card; para criar, usar `create_pipeline_item` antes).
- `assign_pipeline_item_agent(params)` / `assign_pipeline_item_team(params)` — mesmo padrão de
  resolução; atualiza `assignee_id`/`team_id`. Reaproveita `assignee_must_be_pipeline_member`
  como guarda natural (já existe no model).
- `add_pipeline_item_label(params)` / `remove_pipeline_item_label(params)` — mirror de
  `add_label`/`remove_label` já existentes na classe-base `ActionService`, usando o `Labelable`
  já incluído em `PipelineItem`.
- `update_pipeline_item(params)` — `[{ pipeline_id:, title:, value:, notes: }]` (qualquer
  subconjunto presente), `.update!` simples no item resolvido.
- `export_pipeline_item(params)` — `[{ pipeline_id:, target_pipeline_id:, target_stage_id: }]`
  — delega para `Pipelines::ExportItemService.new(pipeline_item: resolvido, target_pipeline:, target_stage_id:).perform`.
  Erros específicos (`SamePipelineError`, `InvalidTargetStageError`, `RecordInvalid` por card
  duplicado no destino) já caem no rescue genérico por-ação existente — não precisa de
  tratamento extra aqui.

## 2. Helper privado compartilhado

```ruby
def resolve_pipeline_item_for_conversation(pipeline_id)
  @account.pipeline_items.find_by(pipeline_id: pipeline_id, contact_id: @conversation.contact_id)
end
```

Usado por `move_pipeline_item_stage`, `assign_pipeline_item_agent`,
`assign_pipeline_item_team`, `add_pipeline_item_label`, `remove_pipeline_item_label`,
`update_pipeline_item`, `export_pipeline_item`. Cada chamador faz `return if item.nil?` com um
log de info — nunca levantar erro só por não existir card ainda.

## 3. Whitelist

`app/models/automation_rule.rb#actions_attributes` (linha 42-47) — adicionar as 8 novas ações:
`create_pipeline_item move_pipeline_item_stage assign_pipeline_item_agent
assign_pipeline_item_team add_pipeline_item_label remove_pipeline_item_label
update_pipeline_item export_pipeline_item`.

Ficam na lista CE (não em `enterprise/app/models/enterprise/automation_rule.rb`) — decisão já
confirmada com o cliente de manter pipeline como recurso CE.

## 4. Verificar strong params (ponto de risco explícito, verificar ANTES de assumir que já
## funciona)

`app/controllers/api/v1/accounts/automation_rules_controller.rb#automation_rules_permit` hoje
permite `actions: [:action_name, { action_params: [] }]`. Essa forma (`action_params: []`)
permite array de valores escalares — **não está confirmado** que ela de fato aceita um array
contendo um hash (`[{pipeline_id:, pipeline_stage_id:, ...}]`), mesmo que `send_email_to_team`
já use esse formato hoje em produção.

- Escrever um teste de controller isolado (ou testar via console Rails) enviando um
  `action_params` no formato hash através deste permit e confirmar se o hash chega intacto ou
  é filtrado.
- Se filtrado: ajustar para `action_params: [{}]` (forma do Rails para "array de hashes,
  permite todas as chaves de cada hash") ou tratamento manual equivalente, testando que os
  formatos antigos (`add_label` com array de strings, `send_email_to_team` com hash) continuam
  funcionando após o ajuste.

## Testes

`spec/services/automation_rules/action_service_spec.rb` (arquivo existente — estender) — um
exemplo por ação nova cobrindo:
- Caminho feliz (ação aplica a mudança esperada).
- No-op silencioso quando não existe card do contato naquele pipeline (para as ações que
  dependem de card existente).
- `create_pipeline_item` falhando por duplicidade (contato já tem card no pipeline) — deve
  logar via `ChatwootExceptionTracker` e a regra deve continuar rodando as demais ações sem
  crashar.

## Critério de pronto

- 8 novas ações implementadas e testadas em `action_service_spec.rb`.
- Confirmação (com teste ou verificação manual documentada) de que o strong params aceita o
  formato hash necessário — com o ajuste aplicado se não aceitar.
- `bundle exec rubocop -a` limpo nos arquivos tocados.
