# Task: Consolidar fallback de capacidade v2 duplicado (código morto em `inbox_agent_availability.rb`)

## Objetivo

A task `07` (fallback anti-silêncio) foi aplicada literalmente nos dois arquivos que o
spec indicava, mas um deles é **código morto** — nunca executa em produção. O resultado
é duas cópias quase idênticas da mesma lógica de fallback de capacidade (v2,
`agent_capacity_policy`): uma viva, uma morta. Esta task consolida em um único lugar.

Não é uma regressão funcional (o comportamento correto já está ativo hoje, coberto por
spec) — é uma limpeza de duplicação/código morto que, se deixada, vai confundir quem
tentar debugar ou estender esse fallback no futuro.

---

## Contexto importante

`Inbox` (`app/models/inbox.rb:47`) faz `include InboxAgentAvailability`.
`InboxAgentAvailability.prepend_mod_with('InboxAgentAvailability')`
(`app/models/concerns/inbox_agent_availability.rb:34`) prepende
`Enterprise::InboxAgentAvailability` **nesse módulo**, não na classe `Inbox`.

Só que `Inbox.prepend_mod_with('Inbox')` (`app/models/inbox.rb:265`) prepende
`Enterprise::Inbox` **direto na classe** `Inbox`. Em Ruby, um módulo prependado
diretamente na classe sempre vence, na resolução de método, qualquer módulo alcançado só
via `include` (mesmo que esse módulo tenha, por sua vez, algo prependado nele). Cadeia
real de ancestrais de `Inbox`:

```
[Enterprise::Inbox, Inbox, AccountCacheRevalidator, OutOfOffisable, Avatarable,
 Reportable, ..., Enterprise::InboxAgentAvailability, InboxAgentAvailability, ...]
```

Isso significa que `inbox.member_ids_with_assignment_capacity` **sempre** resolve para
`Enterprise::Inbox#member_ids_with_assignment_capacity`
(`enterprise/app/models/enterprise/inbox.rb:4`) primeiro — nunca chega em
`Enterprise::InboxAgentAvailability#member_ids_with_assignment_capacity`
(`enterprise/app/models/enterprise/inbox_agent_availability.rb:4`) como entry point.
Isso já era verdade **antes** desta feature (não é uma regressão introduzida agora).

O implementador da task `07` percebeu esse shadowing (ver comentário dele em
`enterprise/app/models/enterprise/inbox.rb:36-39`) e reagiu criando um método novo,
não previsto no spec da task `07`, no arquivo que de fato é alcançado:

`enterprise/app/models/enterprise/inbox.rb`:
```ruby
def member_ids_with_assignment_capacity
  return super unless enable_auto_assignment?
  return member_ids_with_capacity_fallback if auto_assignment_v2_enabled?
  ...
end

private

# V2 capacity path (agent_capacity_policy). `filter_by_capacity` is the actually-reachable
# method here — Enterprise::InboxAgentAvailability#member_ids_with_assignment_capacity is
# shadowed by this method (Enterprise::Inbox is prepended ahead of it in the ancestor chain)
# and never runs, so the fallback belongs here, not there.
def member_ids_with_capacity_fallback
  eligible = available_agents
  with_capacity = filter_by_capacity(eligible)
  return with_capacity.map(&:user_id) if with_capacity.present? || eligible.blank?

  Rails.logger.warn(
    "[AutoAssignment::Fallback] inbox_id=#{id} account_id=#{account_id} " \
    "filter=agent_capacity_policy eligible_before=#{eligible.map(&:user_id)} " \
    'reason=all_agents_over_capacity action=ignoring_limit_as_last_resort'
  )
  eligible.map(&:user_id)
end
```

Enquanto isso, `enterprise/app/models/enterprise/inbox_agent_availability.rb` ainda tem
o diff literal da task `07` aplicado — spec-compliant, mas morto:

```ruby
module Enterprise::InboxAgentAvailability
  extend ActiveSupport::Concern

  def member_ids_with_assignment_capacity
    return member_ids unless capacity_filtering_enabled?

    agents = available_agents
    with_capacity = filter_by_capacity(agents)
    return with_capacity.map(&:user_id) if with_capacity.present? || agents.blank?

    Rails.logger.warn(
      "[AutoAssignment::Fallback] inbox_id=#{id} account_id=#{account_id} " \
      "filter=agent_capacity_policy eligible_before=#{agents.map(&:user_id)} " \
      'reason=all_agents_over_capacity action=ignoring_limit_as_last_resort'
    )
    agents.map(&:user_id)
  end

  private

  def filter_by_capacity(inbox_members_scope)
    ...
  end
  ...
end
```

`filter_by_capacity`, `capacity_filtering_enabled?` e `capacity_service` (privados neste
módulo) **continuam sendo usados** — são chamados de dentro de
`member_ids_with_capacity_fallback` em `enterprise/inbox.rb`, que os alcança porque
ainda fazem parte da cadeia de ancestrais do objeto `Inbox` (só o método de entrada
`member_ids_with_assignment_capacity` deste módulo é que está inacessível). Ou seja: não
dá para simplesmente apagar o módulo inteiro — só o método de entrada duplicado é morto.

Confirmar por busca (`grep -rn member_ids_with_assignment_capacity`) que todo call site
real (`app/models/concerns/auto_assignment_handler.rb`,
`app/models/concerns/assignment_handler.rb`, specs) chama
`inbox.member_ids_with_assignment_capacity` — nunca invoca o método do módulo
`Enterprise::InboxAgentAvailability` isoladamente.

---

## O que precisa ser decidido/feito

Consolidar a lógica de fallback de capacidade v2 em **um único lugar**, eliminando a
duplicação. Duas abordagens possíveis (avaliar qual se encaixa melhor no estilo do
projeto antes de implementar):

1. **Remover o método morto**: apagar (ou reduzir a um comentário explicativo, sem
   lógica) o `member_ids_with_assignment_capacity` de
   `enterprise/inbox_agent_availability.rb`, deixando claro no código que ele é
   inalcançável e por quê — manter só os métodos privados (`filter_by_capacity` etc.)
   que continuam em uso via `enterprise/inbox.rb`.
2. **Religar a cadeia de `super`**: investigar se é possível reestruturar para que
   `Enterprise::Inbox#member_ids_with_assignment_capacity` (branch v2) efetivamente
   delegue para `Enterprise::InboxAgentAvailability#member_ids_with_assignment_capacity`
   em vez de duplicar o corpo — mais fiel ao spec original da task `07`, mas exige
   entender melhor as restrições de `prepend_mod_with` no projeto antes de mexer (pode
   não ser trivial sem também mudar onde `Enterprise::Inbox` é prependado).

Qualquer que seja a abordagem escolhida, documentar (comentário curto no código) o
comportamento de `prepend_mod_with`: prepend em classe sempre vence prepend em módulo
incluído — é uma pegadinha não óbvia que pode se repetir em futuras extensões
enterprise deste projeto.

---

## Verificação

- `spec/enterprise/models/inbox_spec.rb` (teste de fallback de
  `member_ids_with_assignment_capacity` no fluxo v2) deve continuar passando sem
  alteração de comportamento — só a duplicação de código muda, não o resultado.
- Confirmar via `bin/rails console` ou teste novo que
  `Inbox.ancestors.select { |m| m.to_s.include?('InboxAgentAvailability') ||
  m.to_s.include?('Enterprise::Inbox') }` mostra a ordem esperada, e que o método
  removido/consolidado realmente não é mais um caminho de código paralelo.
- `bundle exec rubocop` limpo nos arquivos alterados.
