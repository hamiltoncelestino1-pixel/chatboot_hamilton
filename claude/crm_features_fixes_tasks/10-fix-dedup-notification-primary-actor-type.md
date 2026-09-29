# Task 10 — Fix: dedup de notificação apaga registro legítimo por colisão de ID entre tipos

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/jobs/notification/remove_duplicate_notification_job.rb:11`:

```ruby
Notification.where(user_id: user_id, primary_actor_id: primary_actor_id)
```

Esse job pré-existente assumia implicitamente que `primary_actor_id` sozinho já identificava a
origem de uma notificação — verdade só enquanto `Notification::PRIMARY_ACTORS` continha
apenas `Conversation`. Hoje `PRIMARY_ACTORS = %w[Conversation Task PipelineItem]`
(`app/models/notification.rb`), e `Task`, `PipelineItem` e `Conversation` têm sequences de ID
independentes — o mesmo número de ID pode existir simultaneamente nas 3 tabelas.

**Cenário concreto**: usuário tem uma notificação vinculada a `Conversation#100`. Depois,
`Task#100` (mesmo ID, entidade completamente diferente) vence e gera uma notificação
`task_due` pro mesmo usuário. O job trata como duplicata (mesmo `user_id` + mesmo
`primary_actor_id`, ignorando o tipo) e destrói a notificação mais antiga — perda silenciosa de
uma notificação de conversa legítima, por pura coincidência numérica de ID.

Este arquivo não foi tocado nem pelo épico de Tasks original (`claude/tasks_tasks/`) nem pela
auditoria de 2026-08-16 (`claude/crm_optimizacao_tasks/`) — é uma regressão de integridade de
dados causada indiretamente pela adição de novos `primary_actor_type`, nunca revisada até
agora.

## O que corrigir

Adicionar `primary_actor_type: primary_actor_type` (ou equivalente) ao `where` da query de
dedup, escopando corretamente por tipo além de por ID.

## Testes

Testar manualmente (ou via `rails console`): criar uma `Notification` com
`primary_actor_type: 'Conversation', primary_actor_id: N` e outra com
`primary_actor_type: 'Task', primary_actor_id: N` (mesmo N) para o mesmo usuário, rodar o job
de dedup, confirmar que **nenhuma** das duas é removida por engano.

## Critério de pronto

- Dedup de notificação escopa corretamente por `primary_actor_type` além de
  `primary_actor_id`.
- Notificações de tipos diferentes com IDs numericamente coincidentes não são mais tratadas
  como duplicatas entre si.
- `bundle exec rubocop -a` limpo no arquivo tocado.
