# Task 01 — Fix: push notification de `task_due` quebra o job e reenvia push duplicado

Severidade: 🔴 Crítico. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`Notification::PushNotificationService` (`app/services/notification/push_notification_service.rb`)
assume, em 3 pontos, que `notification.primary_actor` é sempre uma `Conversation`:

```ruby
def conversation
  @conversation ||= notification.conversation
end

def push_message
  {
    title: notification.push_message_title,
    tag: "#{notification.notification_type}_#{conversation.display_id}_#{notification.id}",
    url: push_url
  }
end

def push_url
  app_account_conversation_url(account_id: conversation.account_id, id: conversation.display_id)
end
```

`notification.conversation` é só `primary_actor` (`app/models/notification.rb:134-136`).
Para `task_due`, `primary_actor` é um `Task` (`Notification::PRIMARY_ACTORS = %w[Conversation
Task]`, `app/models/notification.rb:57`) — `Task` não tem `display_id`, então
`conversation.display_id` explode com `NoMethodError`.

**Efeito no FCM** (`send_fcm_push`, linhas 90-100): a chamada `fcm.send_v1(...)` (linha 98)
já envia o push com sucesso ao dispositivo **antes** do crash — que só acontece depois, em
`remove_subscription_if_error` (linha 118-124) ao tentar logar `push_message[:title]`.
`send_fcm_push` não tem `rescue`, então `Tasks::NotifyDueTaskJob#perform` falha inteiro. Como
o `task.update_column(:reminder_sent_at, ...)` (`app/jobs/tasks/notify_due_task_job.rb:15`)
só roda depois de `NotificationBuilder...perform` completar sem erro, o Sidekiq retry
reprocessa o job do zero e **reenvia o mesmo push** a cada tentativa, até esgotar as
retries configuradas.

**Efeito no browser push** (`send_browser_push`, linhas 66-73): o crash acontece dentro de
`browser_push_payload` (linha 51, `JSON.generate(push_message)`), **antes** de
`WebPush.payload_send` ser chamado — mas aqui há um `rescue StandardError => e` (linha 71)
que captura o erro e manda pro Sentry via `handle_browser_push_error`. Resultado: o push web
simplesmente nunca é enviado para `task_due`, silenciosamente (sem crash visível, sem retry,
sem push).

Já está correto (não mexer): `Notification#push_message_title`/`#push_message_body`
(`app/models/notification.rb:90-132`) tratam `task_due` explicitamente por tipo (usam
`primary_actor.title`/`primary_actor.due_date`, nunca `conversation`). O bug está isolado no
serviço de push, que reimplementa sua própria lógica de `tag`/`url` em vez de reusar essa
ramificação já correta do model.

## O que corrigir

Fazer `PushNotificationService` ramificar por `notification.primary_actor_type` (ou
`notification.notification_type`) nos 3 pontos que hoje assumem `Conversation`:

1. `tag` do push (`push_message`, linha 36) — não pode depender de `conversation.display_id`
   para `task_due`. Usar algo estável e único que não dependa de conversa, ex.
   `"#{notification.notification_type}_#{notification.primary_actor_id}_#{notification.id}"`
   (funciona para os dois tipos, não só task).
2. `push_url` (linha 41-43) — para `task_due`, não existe uma conversa pra linkar. Definir
   destino apropriado: se a task tiver `pipeline_item_id`, linkar pro card de pipeline
   (checar rota do frontend do Kanban, ex. `routes/dashboard/kanban/`); senão, linkar pra
   tela de tasks do contato/conversa relacionada, ou uma URL de fallback razoável (decidir
   com base no que já existe de rota no frontend — não inventar rota nova só para isso).
3. Confirmar que `conversation` (linha 29-31) só é chamado nos caminhos onde
   `primary_actor` de fato é uma `Conversation` — não precisa mudar esse método em si, só
   os 2 pontos que o chamam incondicionalmente.

Depois do fix, **testar manualmente os outros 8 tipos de notificação** (não só `task_due`)
para garantir que a ramificação não quebrou o caminho existente — ver risco 1 do
`00-visao-geral.md`.

## Testes

Não é pedido escrever specs a menos que solicitado explicitamente (`AGENTS.md`), mas dado que
é um bug de produção com efeito de duplicidade de push, vale confirmar manualmente no Docker
local: criar uma `Task` com `due_date` no passado, rodar `Tasks::TriggerDueTasksJob` e
`Tasks::NotifyDueTaskJob` manualmente (`rails runner` ou console), confirmar que:
- Nenhum `NoMethodError` é levantado.
- `task.reminder_sent_at` é setado após rodar (prova que o job completou sem crash).
- Push (se subscription de teste configurada) chega com título/corpo corretos, uma única vez.

## Critério de pronto

- `PushNotificationService` funciona para `task_due` sem `NoMethodError`, em FCM e browser
  push.
- Push de `task_due` não é reenviado em duplicidade (job completa e marca
  `reminder_sent_at` numa única execução).
- Os 8 outros tipos de notificação continuam funcionando sem regressão (teste manual).
- `bundle exec rubocop -a` limpo no arquivo tocado.
