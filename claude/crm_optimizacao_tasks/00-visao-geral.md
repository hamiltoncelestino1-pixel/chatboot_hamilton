# Visão Geral — Otimização do CRM (Pipeline/Kanban + Tasks)

## Objetivo

Passada de otimização sobre as duas features de CRM já implementadas (Kanban/Pipeline e
Tasks/follow-up), construídas em ciclos separados sem revisão de performance depois.
Cobre 3 frentes: (1) corrigir bugs reais encontrados na auditoria, (2) reduzir queries/
requests desnecessários, (3) padronizar código que destoa do resto do projeto.

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task independente.
Nenhuma task foi implementada ainda — são achados de uma análise de viabilidade
(2026-08-16) prontos para pegar e corrigir, um de cada vez.

## Como esta auditoria foi feita

3 agentes Explore em paralelo (backend Pipeline, frontend Pipeline, feature Tasks ponta
a ponta), seguido de verificação manual — leitura direta do arquivo citado — de cada
achado antes de virar task. Nenhum item abaixo é especulativo.

## Ordem de execução recomendada

| # | Task | Severidade | Área |
|---|------|------------|------|
| [01](01-fix-push-notification-task-due.md) | Push notification de `task_due` quebra o job e reenvia push duplicado | 🔴 Crítico | Backend/Tasks |
| [02](02-fix-reorder-pipeline-items-nplus1.md) | `reorder` de card do Kanban faz 2N queries | 🟠 Alta | Backend/Pipeline |
| [03](03-fix-items-count-nplus1-pipelines.md) | N+1 de `items_count` em `PipelinesController#index`/`show` | 🟠 Alta | Backend/Pipeline |
| [04](04-padronizar-filtro-pipeline-id.md) | Join redundante em vez da coluna `pipeline_id` direta (4 pontos) | 🟠 Alta | Backend/Pipeline |
| [05](05-fix-includes-desnecessarios-tasks-controller.md) | `includes` de associações nunca usadas em `TasksController#index` | 🟠 Alta | Backend/Tasks |
| [06](06-fix-claim-trigger-due-tasks-job.md) | `TriggerDueTasksJob` sem claim antes de enfileirar (risco de duplicidade) | 🟠 Alta | Backend/Tasks |
| [07](07-fix-watch-deep-kanban.md) | `{ deep: true }` desnecessário em 2 watchers do Kanban | 🟡 Média | Frontend/Pipeline |
| [08](08-fix-dispatches-duplicados-kanban.md) | Dispatches HTTP duplicados ao abrir o Kanban | 🟡 Média | Frontend/Pipeline |
| [09](09-padronizar-moeda-kanban-card.md) | Moeda `pt-BR`/`BRL` hardcoded no card do Kanban | 🟢 Baixa | Frontend/Pipeline |
| [10](10-limpeza-scope-morto-label.md) | Scope morto `Label.for_pipelines` | 🟢 Baixa | Backend/Pipeline |
| [11](11-fix-task-drop-contact-name.md) | `TaskDrop#contact_name` quebra padrão defensivo dos outros Drops | 🟢 Baixa | Backend/Tasks |
| [12](12-fix-i18n-pt-br-task-due-settings.md) | i18n `pt_BR` incompleto para `task_due` em `settings.json` | 🟢 Baixa | Frontend/Tasks |

Tasks 01-06 = **Grupo A** (bugs + performance de maior impacto, backend). Tasks 07-08 =
**Grupo B** (performance frontend). Tasks 09-12 = **Grupo C** (padronização/cosmético,
qualquer ordem, independentes entre si).

## Padrões existentes no código que estas tasks devem seguir (não reinventar)

- Batch update pré-carregado com `index_by(&:id)` antes do loop →
  `PipelineStagesController#reorder` (`app/controllers/api/v1/accounts/pipeline_stages_controller.rb:30-44`)
  — referência para a task 02.
- `includes` correto antes de serializar contagem de associação →
  `PipelineStagesController#index` (`app/controllers/api/v1/accounts/pipeline_stages_controller.rb:7`)
  — referência para a task 03.
- Filtro direto pela coluna `pipeline_id` (sem `joins(:pipeline_stage)`) →
  `PipelineItemsController#create`/`#reorder` (`app/controllers/api/v1/accounts/pipeline_items_controller.rb:29,66`)
  — referência para a task 04, que já existe no mesmo arquivo mas não é usada em 4 outros pontos.
- `Notification#push_message_title`/`#push_message_body`
  (`app/models/notification.rb:90-132`) já ramificam corretamente por
  `notification_type`, incluindo `task_due` — referência para a task 01, cujo bug está
  isolado em `Notification::PushNotificationService`, que reimplementa sua própria
  lógica de `tag`/`url` assumindo sempre `Conversation`.

## Riscos consolidados (ver detalhe em cada task)

1. Task 01 mexe em código compartilhado por todos os 9 tipos de notificação, não só
   `task_due` — testar manualmente que os outros tipos continuam funcionando depois da
   mudança.
2. Task 04 muda 4 pontos que decidem o que o usuário pode ver/acessar (autorização por
   escopo de pipeline) — validar que o resultado retornado é idêntico antes/depois.
3. Tasks 02 e 06 tocam jobs/controllers que rodam em produção sem cobertura de teste
   automatizado hoje — testar manualmente no Docker local (reorder de card arrastado no
   Kanban; ciclo completo do job de tarefa vencida) antes de considerar concluído.
4. Task 12 é a única que toca `pt_BR` fora do domínio kanban/automation/macros — não é
   a regra geral do projeto (`AGENTS.md`: só `en` fora dessa exceção), mas está
   completando uma sincronização que o commit `5b903ade2` já começou em
   `generalSettings.json` e deixou pela metade em `settings.json`.

## Backlog de novas features (não são tasks, aguardando priorização do usuário)

Ideias que emergem naturalmente da infraestrutura que já existe (automação de pipeline,
macros, eventos nativos, job periódico de tasks). Nenhuma tem task criada ainda:

1. **Automação cria Task automaticamente** — `AutomationRules::ActionService` já
   suporta ações de pipeline; "criar tarefa" como mais uma ação é extensão natural
   (já citada como fora de escopo da v1 de Tasks em `claude/tasks_tasks/00-visao-geral.md`).
2. **"Motivo de perda"** ao mover card pro estágio `lost` — comum em CRM para
   relatório de funil; `PipelineItem` não tem esse campo hoje.
3. **Alerta de card parado** (sem movimento de estágio há X dias) — mesmo modelo de
   job periódico que `Tasks::TriggerDueTasksJob` já usa.
4. **Badge de tarefa vencida no card do Kanban** — a integração de tasks no card já
   existe (`KanbanCardDetail.vue`), mas não há indicador visual na lista sem abrir o card.
5. **Relatório de funil** (conversão por estágio, tempo médio por estágio, valor total
   em aberto) — estrutura de dados (`PipelineItem`/`PipelineStage`) já suporta, falta a
   camada de agregação/UI.
6. **Recorrência de tarefas** — também fora de escopo da v1, já documentado como
   extensão futura.
