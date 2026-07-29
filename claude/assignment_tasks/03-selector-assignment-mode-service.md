# Task: Selector usa `assignment_mode` da inbox sem exigir `AssignmentPolicy`

## Objetivo

Hoje o `AssignmentService` só escolhe o algoritmo "balanced" (least-busy) se a inbox tiver uma
`AssignmentPolicy` vinculada com `assignment_order: balanced`. Esta task adiciona um caminho
direto: se a inbox tiver `auto_assignment_config['assignment_mode'] == 'balanced'` (setado via
task `02`/UI da task `04`), usa o `BalancedSelector` **mesmo sem nenhuma Policy vinculada** —
mantendo compatibilidade total com quem já usa Policy (ela continua tendo precedência).

Depende das tasks `01` (feature `advanced_assignment` habilitada globalmente) e `02` (campo
validado e liberado no controller).

---

## Contexto importante

Ponto de decisão atual, `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb`:
```ruby
def find_available_agent(conversation = nil)
  agents = filter_agents_by_team(inbox.available_agents, conversation)
  return nil if agents.nil?

  agents = filter_agents_by_rate_limit(agents)
  agents = filter_agents_by_capacity(agents) if capacity_filtering_enabled?
  return nil if agents.empty?

  # Use balanced selector only if advanced_assignment feature is enabled
  selector = policy&.balanced? && account.feature_enabled?('advanced_assignment') ? balanced_selector : round_robin_selector
  selector.select_agent(agents)
end

private

def policy
  @policy ||= inbox.assignment_policy
end

def account
  inbox.account
end

def round_robin_selector
  @round_robin_selector ||= AutoAssignment::RoundRobinSelector.new(inbox: inbox)
end

def balanced_selector
  @balanced_selector ||= Enterprise::AutoAssignment::BalancedSelector.new(inbox: inbox)
end
```

`BalancedSelector` (`enterprise/app/services/enterprise/auto_assignment/balanced_selector.rb`)
já é reaproveitável sem nenhuma mudança — recebe `agents` (lista já filtrada) e não sabe nada
sobre `AssignmentPolicy`:
```ruby
class Enterprise::AutoAssignment::BalancedSelector
  pattr_initialize [:inbox!]
  def select_agent(available_agents)
    return nil if available_agents.empty?
    agent_users = available_agents.map(&:user)
    assignment_counts = fetch_assignment_counts(agent_users)
    agent_users.min_by { |user| assignment_counts[user.id] || 0 }
  end
  ...
end
```

---

## 1. `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb`

```diff
   def find_available_agent(conversation = nil)
     agents = filter_agents_by_team(inbox.available_agents, conversation)
     return nil if agents.nil?

     agents = filter_agents_by_rate_limit(agents)
     agents = filter_agents_by_capacity(agents) if capacity_filtering_enabled?
     return nil if agents.empty?

-    # Use balanced selector only if advanced_assignment feature is enabled
-    selector = policy&.balanced? && account.feature_enabled?('advanced_assignment') ? balanced_selector : round_robin_selector
+    selector = assignment_mode_balanced? ? balanced_selector : round_robin_selector
     selector.select_agent(agents)
   end
+
+  # Prioridade: AssignmentPolicy vinculada > config direta na inbox (auto_assignment_config).
+  # Mesmo no caminho direto (sem policy), respeita o feature flag — se um Super Admin
+  # desabilitar advanced_assignment pontualmente numa conta no futuro, o balanceamento por
+  # carga é desativado ali sem precisar mexer no jsonb de cada inbox individualmente.
+  def assignment_mode_balanced?
+    return false unless account.feature_enabled?('advanced_assignment')
+    return true if policy&.balanced?
+
+    inbox.auto_assignment_config['assignment_mode'] == 'balanced'
+  end
```

Não precisa tocar em `balanced_selector`/`round_robin_selector`/`policy`/`account` — já existem
memoizados exatamente como essa nova implementação precisa.

---

## Verificação

- Estender `spec/enterprise/services/enterprise/auto_assignment/assignment_service_spec.rb`
  (verificar a convenção de setup já usada nesse spec — factories `:inbox`, `:account`,
  `:inbox_member`, mocks de `OnlineStatusTracker`):
  ```ruby
  describe '#assignment_mode_balanced?' do
    context 'sem AssignmentPolicy vinculada' do
      it 'usa balanced quando auto_assignment_config[assignment_mode] == balanced' do
        inbox.update!(auto_assignment_config: { 'assignment_mode' => 'balanced' })
        account.enable_features!('advanced_assignment')
        # ... criar 2 agentes, 1 com mais conversas abertas que o outro ...
        # perform_bulk_assignment deve atribuir ao agente com menos conversas abertas
      end

      it 'usa round robin quando assignment_mode é round_robin ou ausente' do
        # comportamento inalterado
      end

      it 'ignora balanced se advanced_assignment estiver desabilitado na conta' do
        inbox.update!(auto_assignment_config: { 'assignment_mode' => 'balanced' })
        account.disable_features!('advanced_assignment')
        # deve cair para round_robin_selector mesmo com assignment_mode=balanced
      end
    end

    context 'com AssignmentPolicy vinculada' do
      it 'a policy continua tendo precedência sobre a config direta da inbox' do
        # policy.assignment_order = 'balanced', inbox.auto_assignment_config vazio
        # deve usar balanced (comportamento já existente, não pode regredir)
      end
    end
  end
  ```
- Manual: `bin/rails console`,
  ```ruby
  inbox = Inbox.find(X)
  inbox.update!(enable_auto_assignment: true, auto_assignment_config: { assignment_mode: 'balanced' })
  # criar/observar 2+ agentes membros da inbox com quantidades diferentes de conversas abertas
  # disparar Enterprise::AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment
  # confirmar que o agente com menos conversas abertas recebe a próxima
  ```
- Confirmar que uma inbox com `AssignmentPolicy` já vinculada (`assignment_order: balanced`)
  continua funcionando sem nenhuma mudança de comportamento (regressão zero).
- `bundle exec rubocop` limpo.
