# Visão Geral — 6 Features Novas do CRM (Pipeline/Kanban + Tasks)

## Objetivo

Implementar as 6 ideias de feature que ficaram registradas como backlog em
`claude/crm_optimizacao_tasks/00-visao-geral.md`, agora aprovadas pelo usuário: badge de
tarefa vencida no card do Kanban, alerta de card parado, relatório de funil, motivo de
perda ao mover card pra `lost`, automação criando `Task` automaticamente, e recorrência de
tarefas.

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task independente.
Nenhuma task foi implementada ainda — são especificações prontas para pegar e codar, uma de
cada vez. Plano de origem: análise de viabilidade de 2026-08-16 (ver histórico de conversa).

## Decisões de produto já confirmadas com o usuário

- **Motivo de perda** (feature 2): lista configurável por conta (tabela dedicada
  `PipelineLostReason`, padrão `CannedResponse`/`Macro`), **não** texto livre nem custom
  attribute genérico.
- **Recorrência de tarefa** (feature 6): a próxima ocorrência só é criada **ao completar** a
  atual, não por job periódico independente.
- **Relatório de funil** (feature 5): v1 usa a coluna `stage_changed_at` (criada pela
  feature 3) como aproximação de "tempo médio no estágio atual" — não é histórico completo
  de todas as passagens por estágio (isso exigiria uma tabela de log nova, sem dados
  retroativos, fora do escopo desta v1). Deixar isso explícito na UI do relatório.

## Ordem de execução recomendada

| # | Task | Feature | Depende de |
|---|------|---------|------------|
| [01](01-badge-tarefa-vencida-kanban-card.md) | Badge de tarefa vencida no card do Kanban | 4 | — |
| [02](02-schema-stage-changed-at.md) | Schema: coluna `stage_changed_at` em `pipeline_items` | 3 | — |
| [03](03-job-alerta-card-parado.md) | Job + notificação de card parado | 3 | 02 |
| [04](04-backend-relatorio-funil.md) | Backend: builder + endpoint de relatório de funil | 5 | 02 |
| [05](05-frontend-relatorio-funil.md) | Frontend: página de relatório de funil | 5 | 04 |
| [06](06-schema-model-pipeline-lost-reason.md) | Schema + model `PipelineLostReason` | 2 | — |
| [07](07-backend-crud-fluxo-lost-reason.md) | Backend: CRUD de motivos + validação no card | 2 | 06 |
| [08](08-frontend-modal-lost-reason.md) | Frontend: modal de motivo ao mover pra `lost` | 2 | 07 |
| [09](09-automacao-cria-task.md) | Automação de pipeline cria `Task` | 1 | — |
| [10](10-recorrencia-tarefas.md) | Recorrência de tarefas | 6 | — |

Tasks 02-03 = **Grupo A** (card parado). Tasks 04-05 = **Grupo B** (relatório de funil,
depende do Grupo A pela coluna `stage_changed_at`). Tasks 06-08 = **Grupo C** (motivo de
perda). Tasks 01, 09, 10 são independentes entre si e podem ser feitas em qualquer ordem
relativa aos outros grupos.

## Padrões existentes no código que estas tasks devem seguir (não reinventar)

- Job trigger (query em batch + janela de tempo) + job notify individual por registro →
  `Tasks::TriggerDueTasksJob`/`Tasks::NotifyDueTaskJob`
  (`app/jobs/tasks/trigger_due_tasks_job.rb`, `notify_due_task_job.rb`) — referência para a
  task 03. Registrar o trigger em `app/jobs/trigger_scheduled_items_job.rb:24` (já roda via
  cron a cada 5 min, `config/schedule.yml:14-17` — confirmado, não precisa de entrada nova
  no schedule).
- `NotificationBuilder` (`app/builders/notification_builder.rb`) + `Notification::NOTIFICATION_TYPES`
  como hash simples (`app/models/notification.rb:38-48`) — novo tipo não exige migration em
  `notifications`/`notification_settings` (flags de email/push são derivadas
  automaticamente via `FlagShihTzu`) — referência para a task 03.
- Dispatch dinâmico de ação de automação via `send(action[:action_name], action[:action_params])`
  + whitelist em `AutomationRule#actions_attributes` (`app/models/automation_rule.rb:42-49`)
  — referência para a task 09. Primitivas de mutação de pipeline item ficam em
  `app/services/concerns/pipeline_item_actions.rb`, compartilhado por automação e macro.
- Tabela dedicada `belongs_to :account` para lista configurável por conta → padrão de
  `CannedResponse`/`Macro` — referência para a task 06.
- Callback `after_update_commit` guardado por `saved_change_to_X?` → `Task` já usa esse
  padrão para os outros 3 eventos (`app/models/task.rb:53-56`) — referência para a task 10.
- Componentes de relatório existentes (`ReportMetricCard.vue`,
  `shared/components/charts/BarChart.vue`, `ReportPolicy`) — referência para as tasks 04-05,
  sem introduzir biblioteca de gráfico nova.

## Riscos consolidados (ver detalhe em cada task)

1. Tasks 02/03 e 04/05 compartilham a coluna `stage_changed_at` — não inverter a ordem.
2. Task 05 precisa deixar claro na UI que "tempo médio por estágio" é uma aproximação por
   snapshot (cards atualmente no estágio), não histórico completo.
3. Task 08 muda o fluxo de UX de mover card pra `lost` — testar rollback da UI otimista
   tanto em erro de API quanto em cancelamento do modal.
4. Task 09 precisa decidir escopo (só gatilho nativo de pipeline, ou também gatilho de
   conversa) antes de começar.
5. Task 10 precisa decidir callback-no-model vs. listener-de-evento antes de começar.
6. Nenhuma das 6 features tem hoje extensão conhecida em `enterprise/` para as áreas
   tocadas (Pipeline, Task, Notification, Report) — confirmar rapidamente no início de cada
   task (skill `sincronizar-enterprise`) antes de fechar.
7. Contagem agregada da task 01 precisa ser 1 query por request de listagem, não 1 por
   item — não reintroduzir o N+1 que `claude/crm_optimizacao_tasks/03-*.md` acabou de
   corrigir em endpoint irmão.
