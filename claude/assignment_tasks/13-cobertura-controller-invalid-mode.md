# Task: Teste de integração do controller para `assignment_mode` inválido

## Objetivo

A task `02` liberou `assignment_mode`/`restrict_to_online_agents` nos parâmetros
permitidos do controller e adicionou validação de valores aceitos no model
(`ensure_valid_assignment_mode`). Existe teste confirmando que o **model** rejeita um
valor inválido, e teste confirmando que o **controller** aceita um valor válido — mas
nenhum teste confirma o comportamento do controller quando o valor é inválido.

---

## Contexto importante

Cobertura hoje:

- `spec/enterprise/models/inbox_spec.rb`: `ensure_valid_assignment_mode` rejeita
  `'invalid_mode'` no nível de model (`inbox.valid?` retorna `false`).
- `spec/enterprise/controllers/enterprise/api/v1/accounts/inboxes_controller_spec.rb`
  (~linha 69-79): `PATCH` com `assignment_mode: 'balanced'` é aceito e persistido
  (caminho feliz).

Falta: `PATCH` com `assignment_mode` inválido através do controller de verdade. O
comportamento esperado depende de `RequestExceptionHandler` (que já tem
`rescue_from ActiveRecord::RecordInvalid` global, conforme documentado na visão geral —
`00-visao-geral.md`), mas isso nunca foi confirmado com um teste de integração real
passando pela stack completa (params permitidos → model validation → resposta HTTP).

---

## O que precisa ser feito

Adicionar um teste no spec do controller, reaproveitando a mesma estrutura dos testes
"happy path" já existentes no arquivo (mesmo `PATCH`, mesmos headers/autenticação), mas
com `auto_assignment_config: { assignment_mode: 'invalid_mode' }` — e confirmar que a
resposta é um erro (status HTTP de erro de validação, corpo de erro mencionando o campo),
não um 200 silencioso nem um 500.

---

## Verificação

- Novo teste passa com a implementação atual (não deveria exigir nenhuma mudança de
  código de produção — só está fechando um buraco de cobertura).
- Confirmar manualmente (ou via teste) que o registro **não** foi persistido com o valor
  inválido (`inbox.reload.auto_assignment_config['assignment_mode']` continua com o
  valor anterior).
- `bundle exec rubocop` limpo.
