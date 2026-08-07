# Task 21 — Sincronizar assignee/team entre card do Pipeline e Conversa vinculada

Task independente das demais do épico. Objetivo: quando um `PipelineItem` (card) está
vinculado a uma `Conversation` (`pipeline_item.conversation_id`), espelhar `assignee_id`/
`team_id` bidirecionalmente entre os dois — mudar responsável/time no card reflete na
conversa, e vice-versa — controlado por um toggle **"Sincronizar Atribuições"** por pipeline
(`Pipeline#sync_assignments`, desligado por padrão).

Nenhum código `enterprise/` envolvido — `PipelineItem`/`Conversation`/`Pipeline` são models CE
puros, sem mod correspondente a sincronizar.

**Ponto de desenho já validado com o cliente**: a sincronização reage a **eventos já
existentes** (`assignee.changed`, `team.changed` do lado conversa; `pipeline_item.updated` do
lado card), não a controllers individuais — os três pontos de entrada que hoje mudam assignee/
team de conversa (`Conversations::AssignmentService`, `ConversationsController#assign_conversation`,
`BulkActionsJob`) todos passam por `conversation.save`, que já dispara os eventos certos, então
plugar num controller específico deixaria brechas.

**Anti-loop**: a mitigação é convergência por valor, não uma flag tipo `Current.executed_by`.
Card muda assignee A→B → sincroniza pra conversa (A→B, muda de verdade, dispara evento de
volta) → listener de volta vê que o card já está em B (igual ao que acabou de receber) → **não
escreve nada** → sem mudança, sem evento novo, a cadeia morre em 2 saltos. Não usar
`Current.executed_by`/`thread_mattr_accessor` como guarda — esse padrão é thread-local e não
sobrevive ao listener rodando num job Sidekiq separado (thread/processo diferente de quem
disparou o evento).

## 1. Migration + expor o toggle no backend

**Arquivo novo:** `db/migrate/<timestamp>_add_sync_assignments_to_pipelines.rb`, mirror exato
de `db/migrate/20260701100010_add_auto_assignment_to_pipelines.rb`:
```ruby
class AddSyncAssignmentsToPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :pipelines, :sync_assignments, :boolean, null: false, default: false
  end
end
```

**Arquivos a editar:**
- `app/controllers/api/v1/accounts/pipelines_controller.rb` — `pipeline_params` (linha ~32)
  ganha `:sync_assignments`.
- `app/views/api/v1/models/_pipeline.json.jbuilder` — expor `json.sync_assignments
  resource.sync_assignments`.

## 2. `app/models/pipeline_item.rb` — payload do evento precisa de `changed_attributes`

**Por quê:** o listener novo roda assíncrono (`EventDispatcherJob`/Sidekiq), que recarrega o
`PipelineItem` via GlobalID num processo/thread diferente — nesse ponto
`saved_change_to_assignee_id?` já é `false` (dirty-tracking não sobrevive à serialização). O
evento precisa carregar o que mudou já congelado no momento do dispatch síncrono, mesmo padrão
que `dispatch_stage_changed_event` já usa pra `previous_stage_id` (linha 126-132).

`dispatch_updated_event` (hoje linhas 140-145):
```ruby
def dispatch_updated_event
  Rails.configuration.dispatcher.dispatch(
    Events::Types::PIPELINE_ITEM_UPDATED, Time.zone.now,
    pipeline_item: self, performed_by: Current.executed_by
  )
end
```
Adicionar `changed_attributes: previous_changes` ao payload (mesma chave/formato que
`Conversation#dispatcher_dispatch` já usa pros eventos `assignee.changed`/`team.changed`).

## 3. `app/services/pipelines/assignment_sync_service.rb` (novo)

Dois métodos de entrada, um por direção:

```ruby
module Pipelines
  class AssignmentSyncService
    def sync_from_pipeline_item(pipeline_item, changed_attributes)
      # 1. return se pipeline_item.conversation_id.blank? ou !pipeline_item.pipeline&.sync_assignments?
      # 2. return se changed_attributes não tem 'assignee_id' nem 'team_id'
      # 3. conversation = pipeline_item.conversation
      # 4. se 'assignee_id' mudou e conversation.assignee_id != pipeline_item.assignee_id:
      #    conversation.update!(assignee_id: pipeline_item.assignee_id) (ou via
      #    Conversations::AssignmentService, decidir na implementação qual caminho evita
      #    melhor o side-effect do risco 3 abaixo)
      # 5. se 'team_id' mudou e conversation.team_id != pipeline_item.team_id:
      #    conversation.update!(team_id: pipeline_item.team_id)
      #    -> ATENÇÃO: Conversation#ensure_assignee_is_from_team (before_save) pode zerar o
      #    assignee que acabou de ser sincronizado no passo 4 se o assignee não for membro do
      #    time novo (risco 3 do plano). Testar a ordem/combinação explicitamente.
    end

    def sync_from_conversation(conversation, changed_attributes)
      # 1. return se changed_attributes não tem 'assignee_id' nem 'team_id'
      # 2. items = PipelineItem.where(conversation_id: conversation.id).joins(:pipeline)
      #                        .merge(Pipeline.where(sync_assignments: true))
      #    -> uma conversa pode estar vinculada a cards de pipelines DIFERENTES
      #    (conversation_id não é único por pipeline_item) - iterar todos, não assumir "o" card
      # 3. items.each do |item|
      #      # assignee: checar elegibilidade ANTES de escrever -
      #      # pipeline.members.exists?(id: conversation.assignee_id) || conversation.assignee&.administrator?
      #      # se não elegível: log-and-skip (mirror de PipelineItemActions#log_invalid_team),
      #      # NUNCA deixar o ActiveRecord::RecordInvalid de
      #      # PipelineItem#assignee_must_be_pipeline_member propagar e derrubar o job
      #      # (isso vai acontecer com frequência: Conversations::AssignmentService não
      #      # restringe assignee a nenhum pipeline, então é o caso comum, não uma exceção)
      #      # team: sem validação equivalente hoje, mas confirmar se convém reaproveitar
      #      # team_belongs_to_account? de PipelineItemActions por consistência
      #    end
    end
  end
end
```

Em ambos os métodos, escrever só se o valor de destino já não for igual ao de origem (guarda
de convergência que resolve o loop, ver seção de anti-loop acima) — isso é o coração do
mecanismo, não pular essa checagem.

Reaproveitar onde fizer sentido: `app/services/concerns/pipeline_item_actions.rb`
(`assign_pipeline_agent`, `assign_pipeline_team` — mas note que `assign_pipeline_agent` NÃO
tem guarda de elegibilidade hoje, o passo 3 acima precisa adicionar a checagem antes de
chamar, não confiar que o método já protege).

## 4. `app/listeners/pipeline_assignment_sync_listener.rb` (novo)

Mirror de `app/listeners/automation_rule_listener.rb` (`Singleton`, herda `BaseListener`,
listener fino que delega pro service):
```ruby
class PipelineAssignmentSyncListener
  include Singleton
  include BaseListener

  def pipeline_item_updated(event)
    pipeline_item, _account = extract_pipeline_item_and_account(event) # confirmar helper certo em BaseListener, ou extrair direto de event.data
    Pipelines::AssignmentSyncService.new.sync_from_pipeline_item(
      event.data[:pipeline_item], event.data[:changed_attributes]
    )
  end

  def assignee_changed(event)
    Pipelines::AssignmentSyncService.new.sync_from_conversation(
      event.data[:conversation], event.data[:changed_attributes]
    )
  end

  def team_changed(event)
    Pipelines::AssignmentSyncService.new.sync_from_conversation(
      event.data[:conversation], event.data[:changed_attributes]
    )
  end
end
```
Registrar em `app/dispatchers/async_dispatcher.rb` (array `listeners`, linhas 11-23 hoje) —
**não** em `config/initializers/event_handlers.rb`, que só faz `load_listeners` genérico e não
precisa de mudança.

## 5. Frontend — toggle "Sincronizar Atribuições"

`app/javascript/dashboard/routes/dashboard/settings/pipelines/PipelineDetail.vue` hoje só tem
3 abas (Stages/Labels/Agents, linhas 24-29) — não existe aba de configurações gerais. Criar
uma 4ª aba (`PIPELINE_MGMT.DETAIL.TABS.SETTINGS`) + componente novo
`PipelineSettingsSection.vue`, mirror de `PipelineLabelsSection.vue`/`PipelineMembersSection.vue`,
com um único toggle "Sincronizar Atribuições" despachando update do pipeline com
`{ sync_assignments: true/false }` (mesma action Vuex já usada por nome/descrição do pipeline).

**Achado incidental, fora de escopo mas registrado**: `Pipeline#enable_auto_assignment`
também não tem UI hoje (é backend-only) — se fizer sentido, dá pra bundlar os dois toggles
nessa mesma aba nova, mas isso é decisão de quem for implementar, não faz parte do pedido
original desta task.

**Nenhuma outra mudança de frontend é necessária.** Os dois canais de tempo real já existem e
cobrem os dois lados sozinhos: escrever no card dispara `pipeline_item.updated` →
`ActionCableListener` → `kanban/applyRealtimePipelineItem`
(`app/javascript/dashboard/helper/actionCable.js:38-39,204-206`); escrever na conversa já tem
o broadcast equivalente do lado `Conversation`. Assim que o backend fizer a escrita espelhada,
as duas telas atualizam sozinhas.

## 6. i18n

**Correção importante em relação ao domínio Kanban**: o toggle fica na tela de configurações
do Pipeline, que usa `app/javascript/dashboard/i18n/locale/en/pipelineMgmt.json` — **não**
`kanban.json`. `pipelineMgmt.json` **não está** na lista de exceção do CLAUDE.md
(`kanban.json`, `automation.json`, `macros.json`), então segue a regra geral: só editar
`en/pipelineMgmt.json`, sem tocar `pt_BR/pipelineMgmt.json` (gerido por Crowdin/comunidade).

## QA manual

- Ligar o toggle num pipeline. Mudar assignee no card → confirmar que a conversa vinculada
  reflete, em tempo real, sem precisar dar refresh.
- Mudar assignee na conversa → confirmar que o card reflete no Kanban em tempo real.
- Mudar assignee + team juntos no card, onde o assignee **não** é membro do time que vai ser
  espelhado pra conversa → confirmar explicitamente se `Conversation#ensure_assignee_is_from_team`
  zera o assignee sincronizado (risco 3) e decidir se esse comportamento é aceitável ou precisa
  de ajuste na ordem de escrita.
- Atribuir a conversa a um agente que **não** é membro do pipeline → confirmar que o card
  **não** quebra (log-and-skip), e que a mudança na conversa em si não é revertida/bloqueada.
- Vincular a mesma conversa a cards de dois pipelines diferentes, ambos com sync ligado →
  mudar assignee na conversa → confirmar que os dois cards refletem.
- Mudar os dois lados quase simultaneamente pra valores diferentes → confirmar que estabiliza
  no último valor escrito (last-write-wins), sem loop nem erro.
- Desligar o toggle → confirmar que muda em qualquer um dos dois lados de novo (não afeta o
  outro).
- Ligar o toggle num pipeline com cards e conversas já divergentes → confirmar que **não** há
  uma varredura retroativa reatribuindo tudo em massa (risco 6) — só passa a sincronizar dali
  pra frente.
- `bundle exec rubocop -a` / `pnpm eslint:fix` nos arquivos tocados.

## Critério de pronto

- Toggle "Sincronizar Atribuições" funcional por pipeline, desligado por padrão.
- Sync bidirecional funcionando nos dois sentidos, em tempo real nas duas telas.
- Guarda de convergência por valor impedindo loop (confirmado no QA de "mudar os dois lados").
- Guarda de elegibilidade de assignee (card) com log-and-skip, sem job falhando.
- Risco do `ensure_assignee_is_from_team` testado e documentado (aceito ou mitigado).
- Conversa vinculada a múltiplos pipelines sincroniza todos os cards elegíveis.
- Nenhuma sincronização retroativa ao ligar o toggle.
- i18n em `en/pipelineMgmt.json` apenas.
