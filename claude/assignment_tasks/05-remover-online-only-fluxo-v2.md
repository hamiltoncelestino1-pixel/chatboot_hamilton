# Task: Fim do "só agente online" no fluxo dominante (`InboxAgentAvailability`)

## Objetivo

Hoje `available_agents` (usado por todo o fluxo v2, community e enterprise, e também
referenciado indiretamente pelo fluxo legado via `member_ids_with_assignment_capacity`) filtra
incondicionalmente por agentes online. Esta task torna esse filtro **condicional** ao novo campo
`auto_assignment_config['restrict_to_online_agents']` (task `02`), com default = **sem
restrição** (qualquer membro da inbox é elegível, online ou não).

Não depende de nenhuma outra task para funcionar sozinha (pode ser feita em paralelo com
`01`-`04`), mas o campo que ela lê só é gravável via UI depois da task `04`.

---

## Contexto importante

Arquivo central, `app/models/concerns/inbox_agent_availability.rb` (usado por
`app/services/auto_assignment/assignment_service.rb#find_available_agent` via
`inbox.available_agents`, tanto na versão community quanto na `enterprise/.../assignment_service.rb`
que faz `prepend_mod_with`):
```ruby
module InboxAgentAvailability
  extend ActiveSupport::Concern

  def available_agents
    online_agent_ids = fetch_online_agent_ids
    return inbox_members.none if online_agent_ids.empty?

    inbox_members
      .joins(:user)
      .where(users: { id: online_agent_ids })
      .includes(:user)
  end

  def member_ids_with_assignment_capacity
    member_ids
  end

  private

  def fetch_online_agent_ids
    OnlineStatusTracker.get_available_users(account_id)
                       .select { |_key, value| value.eql?('online') }
                       .keys
                       .map(&:to_i)
  end
end

InboxAgentAvailability.prepend_mod_with('InboxAgentAvailability')
```

Confirmado por busca: `available_agents` só é chamado a partir de 2 lugares em produção
(`app/services/auto_assignment/assignment_service.rb` e o override enterprise), e
`OnlineStatusTracker` é usado em outros ~8 arquivos não relacionados a atribuição (mailer,
`room_channel`, indicador de status do agente na UI, etc.) — nenhum deles passa por este
concern, então o raio de impacto desta mudança é isolado à elegibilidade de auto-assignment, sem
afetar o indicador visual de "agente online" no dashboard.

---

## 1. `app/models/concerns/inbox_agent_availability.rb`

```diff
 module InboxAgentAvailability
   extend ActiveSupport::Concern

   def available_agents
+    return inbox_members.joins(:user).includes(:user) unless restrict_to_online_agents?
+
     online_agent_ids = fetch_online_agent_ids
     return inbox_members.none if online_agent_ids.empty?

     inbox_members
       .joins(:user)
       .where(users: { id: online_agent_ids })
       .includes(:user)
   end

   def member_ids_with_assignment_capacity
     member_ids
   end

   private

+  def restrict_to_online_agents?
+    ActiveModel::Type::Boolean.new.cast(auto_assignment_config['restrict_to_online_agents'])
+  end
+
   def fetch_online_agent_ids
     OnlineStatusTracker.get_available_users(account_id)
                        .select { |_key, value| value.eql?('online') }
                        .keys
                        .map(&:to_i)
   end
 end

 InboxAgentAvailability.prepend_mod_with('InboxAgentAvailability')
```

`restrict_to_online_agents?` fica neste módulo **community** (`app/`), não em `enterprise/`,
porque `auto_assignment_config` é coluna base do `Inbox` (não é conceito exclusivo enterprise) —
coerente com onde este concern já vive hoje. `ActiveModel::Type::Boolean.new.cast(nil)` retorna
`nil` (falsy), então a ausência da chave no jsonb já significa "sem restrição" (novo default),
sem precisar de um valor explícito gravado.

---

## Verificação

- Novo spec `spec/models/concerns/inbox_agent_availability_spec.rb` (verificar se já existe um
  spec para este concern especificamente, ou se está coberto só indiretamente via
  `spec/models/inbox_spec.rb` — seguir a convenção que já existir):
  ```ruby
  describe '#available_agents' do
    context 'quando restrict_to_online_agents está ausente/false' do
      it 'retorna todos os membros da inbox, mesmo offline' do
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
        expect(inbox.available_agents.map(&:user_id)).to match_array(inbox.inbox_members.map(&:user_id))
      end
    end

    context 'quando restrict_to_online_agents é true' do
      it 'mantém o comportamento antigo (só online)' do
        inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => true })
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ online_user.id.to_s => 'online' })
        expect(inbox.available_agents.map(&:user_id)).to eq([online_user.id])
      end

      it 'retorna relação vazia se ninguém estiver online' do
        inbox.update!(auto_assignment_config: { 'restrict_to_online_agents' => true })
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
        expect(inbox.available_agents).to be_empty
      end
    end
  end
  ```
- Estender `spec/enterprise/services/enterprise/auto_assignment/assignment_service_spec.rb`
  com um cenário de ponta a ponta: inbox com `restrict_to_online_agents: false` e um agente
  offline membro da inbox → `perform_bulk_assignment` atribui a esse agente normalmente.
- Manual: `bin/rails console`,
  ```ruby
  inbox = Inbox.find(X)
  inbox.update!(auto_assignment_config: { restrict_to_online_agents: false })
  inbox.available_agents.map(&:user_id) # deve incluir membros offline
  ```
  Confirmar visualmente no dashboard que o badge de "online"/"offline" do agente (widget de
  presença) continua funcionando normalmente — não deve mudar de comportamento, só a
  elegibilidade de auto-assignment.
- `bundle exec rubocop` limpo.
