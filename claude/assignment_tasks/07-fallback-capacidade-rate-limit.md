# Task: Fallback — nunca sem atribuição por capacidade/rate-limit

## Objetivo

Garantir que uma conversa nunca fique sem atribuição só porque todos os candidatos foram
filtrados por **limite de capacidade** (`agent_capacity_policy`/`max_assignment_limit`) ou por
**rate-limit de fair distribution**. Se esses filtros esvaziarem um conjunto que tinha
candidatos antes deles, reverte pro conjunto anterior (ignora o limite como último recurso) e
loga de forma bem visível — nunca silenciosamente.

**Fronteiras que continuam sem fallback** (intencional, não são "esquecimento"): filtro de
**time** (`filter_agents_by_team`) e inbox **sem nenhum membro** — nesses dois casos, ficar sem
atribuição é o comportamento correto.

Depende da task `03` (mesmo método `find_available_agent`, aplicado em sequência).

---

## Contexto importante

`app/services/auto_assignment/rate_limiter.rb#limit` — confirma que o cenário é plausível, não
hipotético:
```ruby
def limit
  config&.fair_distribution_limit.present? ? config.fair_distribution_limit.to_i : 5
end
```
Default de **5 assignments por 5 minutos mesmo sem `AssignmentPolicy` vinculada** — em pico de
tráfego com poucos agentes, é fácil todos baterem esse teto ao mesmo tempo.

`enterprise/app/models/enterprise/inbox.rb#member_ids_with_assignment_capacity` (fluxo legado de
capacidade) hoje **não tem nenhum tratamento** para lista vazia:
```ruby
def member_ids_with_assignment_capacity
  return super unless enable_auto_assignment?
  return filter_by_capacity(available_agents).map(&:user_id) if auto_assignment_v2_enabled?

  max_assignment_limit = auto_assignment_config['max_assignment_limit']
  overloaded_agent_ids = max_assignment_limit.present? ? get_agent_ids_over_assignment_limit(max_assignment_limit) : []
  super - overloaded_agent_ids
end
```

`enterprise/app/models/enterprise/inbox_agent_availability.rb#member_ids_with_assignment_capacity`
(fluxo v2, capacidade por `agent_capacity_policy`) também sem tratamento:
```ruby
def member_ids_with_assignment_capacity
  return member_ids unless capacity_filtering_enabled?
  agents = available_agents
  agents = filter_by_capacity(agents)
  agents.map(&:user_id)
end
```

Ponto principal, `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb`
(já modificado pela task `03` — este diff aplica **depois**):
```ruby
def find_available_agent(conversation = nil)
  agents = filter_agents_by_team(inbox.available_agents, conversation)
  return nil if agents.nil?

  agents = filter_agents_by_rate_limit(agents)
  agents = filter_agents_by_capacity(agents) if capacity_filtering_enabled?
  return nil if agents.empty?

  selector = assignment_mode_balanced? ? balanced_selector : round_robin_selector
  selector.select_agent(agents)
end
```

---

## 1. `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb`

```diff
   def find_available_agent(conversation = nil)
     agents = filter_agents_by_team(inbox.available_agents, conversation)
     return nil if agents.nil?

-    agents = filter_agents_by_rate_limit(agents)
-    agents = filter_agents_by_capacity(agents) if capacity_filtering_enabled?
-    return nil if agents.empty?
+    return nil if agents.empty?
+
+    agents = apply_with_fallback(agents, 'rate_limit', conversation) { |scope| filter_agents_by_rate_limit(scope) }
+    if capacity_filtering_enabled?
+      agents = apply_with_fallback(agents, 'capacity', conversation) { |scope| filter_agents_by_capacity(scope) }
+    end

     selector = assignment_mode_balanced? ? balanced_selector : round_robin_selector
     selector.select_agent(agents)
   end
+
+  # Nunca deixa uma conversa sem atribuição por causa de rate-limit/capacidade — só time
+  # (filter_agents_by_team, acima) ou ausência total de membros são fronteiras rígidas. Se o
+  # filtro esvaziar um conjunto que tinha candidatos antes dele, volta ao conjunto anterior e
+  # loga bem alto — nunca silencioso.
+  def apply_with_fallback(agents, filter_name, conversation)
+    filtered = yield(agents)
+    return filtered if filtered.present?
+
+    Rails.logger.warn(
+      "[AutoAssignment::Fallback] inbox_id=#{inbox.id} account_id=#{account.id} " \
+      "conversation_id=#{conversation&.id} filter=#{filter_name} " \
+      "eligible_before=#{agents.map(&:user_id)} " \
+      'reason=all_agents_excluded_by_filter action=ignoring_filter_as_last_resort'
+    )
+    agents
+  end
```

## 2. `enterprise/app/models/enterprise/inbox.rb` — mesmo tratamento no fluxo legado

```diff
   def member_ids_with_assignment_capacity
     return super unless enable_auto_assignment?
     return filter_by_capacity(available_agents).map(&:user_id) if auto_assignment_v2_enabled?

     max_assignment_limit = auto_assignment_config['max_assignment_limit']
     overloaded_agent_ids = max_assignment_limit.present? ? get_agent_ids_over_assignment_limit(max_assignment_limit) : []
-    super - overloaded_agent_ids
+    eligible = super
+    with_capacity = eligible - overloaded_agent_ids
+    return with_capacity if with_capacity.present? || eligible.blank?
+
+    Rails.logger.warn(
+      "[AutoAssignment::Fallback] inbox_id=#{id} account_id=#{account_id} " \
+      "filter=max_assignment_limit eligible_before=#{eligible} " \
+      'reason=all_agents_over_limit action=ignoring_limit_as_last_resort'
+    )
+    eligible
   end
```

## 3. `enterprise/app/models/enterprise/inbox_agent_availability.rb` — mesmo tratamento (fluxo v2, capacidade por `agent_capacity_policy`)

```diff
   def member_ids_with_assignment_capacity
     return member_ids unless capacity_filtering_enabled?

     agents = available_agents
-    agents = filter_by_capacity(agents)
-    agents.map(&:user_id)
+    with_capacity = filter_by_capacity(agents)
+    return with_capacity.map(&:user_id) if with_capacity.present? || agents.blank?
+
+    Rails.logger.warn(
+      "[AutoAssignment::Fallback] inbox_id=#{id} account_id=#{account_id} " \
+      "filter=agent_capacity_policy eligible_before=#{agents.map(&:user_id)} " \
+      'reason=all_agents_over_capacity action=ignoring_limit_as_last_resort'
+    )
+    agents.map(&:user_id)
   end
```

**Nota de decisão** (avaliada e descartada): considerar promover esses `Rails.logger.warn` para
um evento real via `Rails.configuration.dispatcher.dispatch` (padrão já usado em
`dispatch_assignment_event` no mesmo arquivo) — descartado por ora porque nenhum listener
consumiria esse evento hoje (infraestrutura morta sem um listener real). Se no futuro for
necessário alerta ativo (Slack, e-mail), promover o log estruturado para evento de verdade nesse
momento, com o listener correspondente.

---

## Verificação

- Estender `spec/enterprise/services/enterprise/auto_assignment/assignment_service_spec.rb`:
  ```ruby
  describe 'fallback de rate-limit/capacidade' do
    it 'atribui mesmo quando todos os agentes estouram o rate-limit' do
      # criar policy com fair_distribution_limit baixo, ou usar o default de 5
      # simular 5 assignments recentes pro único agente elegível (track_assignment)
      expect(Rails.logger).to receive(:warn).with(/filter=rate_limit/)
      result = service.perform_for_conversation(conversation) # ou perform_bulk_assignment
      expect(result).to be_truthy # não deve retornar nil/false
      expect(conversation.reload.assignee).to be_present
    end

    it 'atribui mesmo quando todos os agentes estouram a capacidade' do
      # configurar agent_capacity_policy com limite 0 ou já no limite pra todos os membros
      expect(Rails.logger).to receive(:warn).with(/filter=capacity/)
      # ... mesma asserção de que a conversa recebe assignee mesmo assim
    end

    it 'NÃO aplica fallback pro filtro de time (fronteira rígida)' do
      # time sem nenhum membro elegível → find_available_agent continua nil
    end
  end
  ```
- Spec equivalente para o fluxo legado (`spec/enterprise/models/inbox_spec.rb`, método
  `member_ids_with_assignment_capacity`): todos os membros acima de `max_assignment_limit` →
  ainda retorna a lista completa (fallback), não vazia.
- Manual: configurar uma inbox com 1-2 agentes e um `agent_capacity_policy`/`max_assignment_limit`
  bem baixo (ex. 1), gerar conversas suficientes pra estourar o limite de todos, e confirmar que
  as conversas seguintes continuam sendo atribuídas (não ficam em `unassigned`), com o log de
  warn aparecendo no `log/development.log` (ou stdout, conforme configuração).
- Confirmar que uma conversa sem time e sem nenhum membro na inbox **continua** ficando sem
  atribuição (comportamento correto, não deve ser "corrigido" por engano).
- `bundle exec rubocop` limpo.
