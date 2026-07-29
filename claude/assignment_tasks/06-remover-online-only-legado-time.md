# Task: Fim do "só agente online" no fluxo legado / reatribuição por time

## Objetivo

Corrigir o filtro de online **independente** que existe em
`app/services/auto_assignment/agent_assignment_service.rb`. Este arquivo **não** é código morto
mesmo com `assignment_v2` habilitado por padrão — ele é chamado sempre que o `team_id` de uma
conversa muda, via `app/models/concerns/assignment_handler.rb#find_assignee_from_team`,
**independente do valor de `assignment_v2`**. Sem esta task, a task `05` sozinha não é
suficiente: toda reatribuição por time continuaria filtrando por online.

Não depende de nenhuma outra task para funcionar sozinha (pode ser feita em paralelo com
`01`-`05`).

---

## Contexto importante

`app/services/auto_assignment/agent_assignment_service.rb` (completo):
```ruby
class AutoAssignment::AgentAssignmentService
  pattr_initialize [:conversation!, :allowed_agent_ids!]

  def find_assignee
    round_robin_manage_service.available_agent(allowed_agent_ids: allowed_online_agent_ids)
  end

  def perform
    new_assignee = find_assignee
    conversation.update(assignee: new_assignee) if new_assignee
  end

  private

  def online_agent_ids
    online_agents = OnlineStatusTracker.get_available_users(conversation.account_id)
    online_agents.select { |_key, value| value.eql?('online') }.keys if online_agents.present?
  end

  def allowed_online_agent_ids
    @allowed_online_agent_ids ||= online_agent_ids & allowed_agent_ids&.map(&:to_s)
  end

  def round_robin_manage_service
    @round_robin_manage_service ||= AutoAssignment::InboxRoundRobinService.new(inbox: conversation.inbox)
  end
end
```

Dois pontos de chamada, ambos precisam do novo comportamento:

1. `app/models/concerns/auto_assignment_handler.rb#run_auto_assignment` — fluxo 100% legado
   (`assignment_v2` desligado na conta):
   ```ruby
   allowed_agent_ids = team_id.present? ? team_member_ids_with_capacity : inbox.member_ids_with_assignment_capacity
   AutoAssignment::AgentAssignmentService.new(conversation: self, allowed_agent_ids: allowed_agent_ids).perform
   ```

2. `app/models/concerns/assignment_handler.rb#find_assignee_from_team` — roda **sempre**,
   mesmo com v2 ligado, toda vez que `team_id` muda:
   ```ruby
   def find_assignee_from_team
     return if team&.allow_auto_assign.blank?
     team_members_with_capacity = inbox.member_ids_with_assignment_capacity & team.members.ids
     ::AutoAssignment::AgentAssignmentService.new(conversation: self, allowed_agent_ids: team_members_with_capacity).find_assignee
   end
   ```

Como os dois passam por `AgentAssignmentService`, a correção neste único arquivo resolve ambos
os pontos de chamada sem duplicar lógica.

---

## 1. `app/services/auto_assignment/agent_assignment_service.rb`

```diff
 class AutoAssignment::AgentAssignmentService
   pattr_initialize [:conversation!, :allowed_agent_ids!]

   def find_assignee
-    round_robin_manage_service.available_agent(allowed_agent_ids: allowed_online_agent_ids)
+    round_robin_manage_service.available_agent(allowed_agent_ids: effective_allowed_agent_ids)
   end

   def perform
     new_assignee = find_assignee
     conversation.update(assignee: new_assignee) if new_assignee
   end

   private

+  def effective_allowed_agent_ids
+    return allowed_agent_ids&.map(&:to_s) unless restrict_to_online_agents?
+
+    allowed_online_agent_ids
+  end
+
+  def restrict_to_online_agents?
+    ActiveModel::Type::Boolean.new.cast(conversation.inbox.auto_assignment_config['restrict_to_online_agents'])
+  end
+
   def online_agent_ids
     online_agents = OnlineStatusTracker.get_available_users(conversation.account_id)
     online_agents.select { |_key, value| value.eql?('online') }.keys if online_agents.present?
   end

   def allowed_online_agent_ids
     @allowed_online_agent_ids ||= online_agent_ids & allowed_agent_ids&.map(&:to_s)
   end

   def round_robin_manage_service
     @round_robin_manage_service ||= AutoAssignment::InboxRoundRobinService.new(inbox: conversation.inbox)
   end
 end
```

`allowed_agent_ids&.map(&:to_s)` no caminho "sem restrição" mantém o mesmo formato de string que
`allowed_online_agent_ids` já produzia (`InboxRoundRobinService#available_agent` espera
`user_id`s como string, vindos originalmente de chaves do Redis — ver
`app/services/auto_assignment/inbox_round_robin_service.rb`), evitando um bug sutil de tipo
(`Integer` vs `String`) na comparação `queue.intersection(allowed_agent_ids)`.

---

## Verificação

- Estender `spec/services/auto_assignment/agent_assignment_service_spec.rb`:
  ```ruby
  describe '#find_assignee' do
    context 'quando restrict_to_online_agents é false/ausente' do
      it 'considera agentes offline como elegíveis' do
        inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => false })
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
        service = described_class.new(conversation: conversation, allowed_agent_ids: [offline_agent.id])
        expect(service.find_assignee).to eq(offline_agent)
      end
    end

    context 'quando restrict_to_online_agents é true' do
      it 'mantém o filtro de online' do
        inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => true })
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
        service = described_class.new(conversation: conversation, allowed_agent_ids: [offline_agent.id])
        expect(service.find_assignee).to be_nil
      end
    end
  end
  ```
- Novo teste (ou extensão de `spec/models/concerns/assignment_handler_spec.rb` se existir)
  cobrindo especificamente `find_assignee_from_team`: mudar `conversation.team_id` para um time
  cujo único membro está offline, com `restrict_to_online_agents: false` na inbox → conversa
  deve ser reatribuída a esse membro (regressão direta do bug que esta task corrige).
- Manual: criar uma conversa, atribuí-la a um time cujo único agente está offline, com a inbox
  configurada `restrict_to_online_agents: false` — confirmar que a conversa recebe esse agente
  como `assignee` (antes desta task, ficaria sem atribuição).
- `bundle exec rubocop` limpo.
