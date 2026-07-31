# Task: Estender asserções de log de fallback para `reason=`/`action=`

## Objetivo

Os testes de fallback anti-silêncio (task `07`) verificam apenas o campo `filter=` da
mensagem de log estruturado, nunca `reason=`/`action=`. Isso deixa um buraco: um
copy-paste incorreto entre os três blocos de `Rails.logger.warn` quase idênticos
(espalhados em `enterprise/inbox.rb`, `enterprise/inbox_agent_availability.rb` e
`enterprise/assignment_service.rb`) que resultasse num `reason=`/`action=` errado não
seria detectado por nenhum teste.

---

## Contexto importante

Os quatro cenários de fallback e seus testes atuais:

- `spec/enterprise/services/enterprise/auto_assignment/assignment_service_spec.rb`
  (~linha 102-146): fallback de rate-limit e de capacidade (`agent_capacity_policy`),
  via `apply_with_fallback` em `enterprise/assignment_service.rb`.
- `spec/enterprise/models/inbox_spec.rb` (~linha 52-57 e ~119-126): fallback de
  `max_assignment_limit` (fluxo legado, `enterprise/inbox.rb`) e de
  `agent_capacity_policy` (fluxo v2 — ver também a task `08`, que pode mudar onde esse
  método vive).

Padrão atual das asserções (repetido nos 4 lugares, só trocando o valor de `filter=`):
```ruby
expect(Rails.logger).to have_received(:warn).with(a_string_matching(/filter=rate_limit/))
```

As mensagens de log reais (`Rails.logger.warn`) seguem o formato
`"[AutoAssignment::Fallback] inbox_id=... account_id=... filter=... eligible_before=...
reason=... action=..."` — cada um dos 3 pontos de origem usa um `reason=`/`action=`
específico (`reason=all_agents_excluded_by_filter`, `reason=all_agents_over_limit`,
`reason=all_agents_over_capacity`, etc.), mas nenhum teste confirma qual é.

---

## O que precisa ser feito

Nos 4 testes de fallback citados acima, estender a asserção de
`have_received(:warn).with(...)` para checar também o `reason=` e `action=` esperados
para cada cenário específico (não só `filter=`) — usando o valor real que cada bloco de
log produz hoje como referência do que deve continuar sendo produzido.

---

## Verificação

- Os 4 testes continuam passando com as mensagens de log atuais.
- Alterar deliberadamente (de forma temporária, só para validar) o `reason=` de um dos
  3 blocos de log e confirmar que o teste correspondente falha — isso confirma que a
  asserção estendida de fato protege contra o copy-paste incorreto entre os blocos.
- `bundle exec rubocop` limpo.
