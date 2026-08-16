# Task 03 — Job + notificação de card parado

Feature 3 (parte 2 de 2). Depende da task 02 (coluna `stage_changed_at`).

## Objetivo

Notificar o `assignee` de um `PipelineItem` quando o card fica parado (sem mudança de
estágio) por mais de X dias, seguindo exatamente o padrão de job + notificação já usado por
`Task`/`task_due`.

## O que criar

**Configuração do limite de dias**: adicionar um campo em `Pipeline` (ex.
`stale_alert_days`, inteiro, com default razoável tipo 7), seguindo o mesmo padrão de
campos já configuráveis por pipeline (`enable_auto_assignment`, `max_assignment_limit` —
conferir a migration desses campos como referência de forma). Se o campo não estiver
configurado (nulo/zero), o job pula esse pipeline (feature desligada por padrão, opt-in por
pipeline — mesma filosofia de "notificação nasce desligada" já usada em
`AccountUser#create_notification_setting`).

**Backend — jobs** (mesmo padrão de `app/jobs/tasks/trigger_due_tasks_job.rb` +
`notify_due_task_job.rb`):

1. `app/jobs/pipeline_items/trigger_stale_items_job.rb`:
   ```ruby
   class PipelineItems::TriggerStaleItemsJob < ApplicationJob
     queue_as :scheduled_jobs

     def perform
       Pipeline.where.not(stale_alert_days: [nil, 0]).find_each do |pipeline|
         pipeline.pipeline_items
                 .joins(:pipeline_stage)
                 .where.not(pipeline_stages: { stage_type: [:won, :lost] })
                 .where(stale_alert_sent_at: nil)
                 .where('stage_changed_at < ?', pipeline.stale_alert_days.days.ago)
                 .find_each(batch_size: 100) do |item|
           PipelineItems::NotifyStaleItemJob.perform_later(item)
         end
       end
     end
   end
   ```
   (ajustar detalhes exatos durante a implementação — ex. se o `where.not` de stage
   terminal deve considerar só `lost`/`won` ou também algum outro `stage_type` futuro).
2. `app/jobs/pipeline_items/notify_stale_item_job.rb`, mesmo padrão de
   `Tasks::NotifyDueTaskJob`:
   ```ruby
   class PipelineItems::NotifyStaleItemJob < ApplicationJob
     queue_as :default

     def perform(pipeline_item)
       return if pipeline_item.assignee.blank? # PipelineItem#assignee é opcional, ao contrário de Task#assignee
       return if pipeline_item.stale_alert_sent_at.present?

       NotificationBuilder.new(
         notification_type: 'pipeline_item_stale',
         user: pipeline_item.assignee,
         account: pipeline_item.account,
         primary_actor: pipeline_item
       ).perform

       pipeline_item.update_column(:stale_alert_sent_at, Time.zone.now)
     end
   end
   ```
   **Atenção ao bug corrigido em `claude/crm_optimizacao_tasks/06-*.md`**: considerar já
   nascer com claim atômico (marcar `stale_alert_sent_at` antes de notificar, não depois),
   em vez de repetir o mesmo problema que a task 06 do épico de otimização corrigiu para
   `Tasks::TriggerDueTasksJob`.
3. Resetar `stale_alert_sent_at` para `nil` quando o card finalmente muda de estágio (no
   mesmo callback `touch_stage_changed_at` da task 02, adicionar
   `self.stale_alert_sent_at = nil`).
4. Registrar em `app/jobs/trigger_scheduled_items_job.rb` (linha 24, mesmo lugar que já
   registra `Tasks::TriggerDueTasksJob.perform_later`) —
   `PipelineItems::TriggerStaleItemsJob.perform_later`. **Não precisa de entrada nova em
   `config/schedule.yml`** — confirmado que `TriggerScheduledItemsJob` já roda via cron a
   cada 5 min (`config/schedule.yml:14-17`).

**Backend — notificação**:

5. `app/models/notification.rb`:
   - `NOTIFICATION_TYPES` (linhas 38-48): adicionar `pipeline_item_stale: 10`.
   - `PRIMARY_ACTORS` (linha 57): adicionar `'PipelineItem'` — `%w[Conversation Task
     PipelineItem]`.
   - `push_message_title`/`push_message_body` (linhas 90-132): branch novo para
     `pipeline_item_stale`, no padrão exato do branch `task_due` já existente (usar
     `primary_actor.title` do card e o número de dias parado).
   - **Atenção ao bug corrigido em `claude/crm_optimizacao_tasks/01-*.md`**: ao implementar
     esta task, `Notification::PushNotificationService` já deve estar corrigido para
     ramificar por `primary_actor_type` em vez de assumir `Conversation` sempre — confirmar
     que esse fix já foi aplicado antes de adicionar mais um tipo que dependeria dele, ou
     aplicar o mesmo cuidado aqui se ainda não corrigido.
6. i18n: `notifications.notification_title.pipeline_item_stale`,
   `notifications.pipeline_item_stale_body` (en, mesma pasta dos outros textos de
   notificação).
7. Mailer/template de email, se a conta tiver `email_pipeline_item_stale` habilitado —
   seguir o padrão de `task_due` (`app/mailers/`, template liquid) confirmado como já
   existente e funcional para `Task`.

## Riscos

- `PipelineItem#assignee` é opcional — ao contrário de `Task`, é preciso pular
  explicitamente cards sem assignee (não faz sentido notificar "ninguém").
- Reaproveitar (não reintroduzir) os dois bugs já corrigidos no épico de otimização: claim
  atômico antes de notificar (evitar duplicidade) e push notification ramificando por tipo
  de ator (evitar crash).

## Testes

Testar manualmente no Docker local: configurar `stale_alert_days` num pipeline, criar um
card com `stage_changed_at` manualmente setado no passado (via console), rodar
`PipelineItems::TriggerStaleItemsJob` manualmente, confirmar que a notificação chega pro
assignee (inbox/sino sempre; email/push se habilitado nas preferências), e que rodar o job
de novo não duplica a notificação.

## Critério de pronto

- Card sem movimento além do limite configurado gera notificação única pro assignee.
- Card sem assignee é pulado sem erro.
- Mover o card de estágio reseta o alerta (pode ser notificado de novo se ficar parado
  outra vez no novo estágio).
- `bundle exec rubocop -a` limpo nos arquivos tocados.
