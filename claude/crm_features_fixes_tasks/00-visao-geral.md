# Visão Geral — Correções pós-implementação do épico CRM (Kanban/Pipeline + Tasks)

## Objetivo

Corrigir os bugs reais encontrados na auditoria de 2026-08-20 sobre o commit `df0251e58`
("feat(crm): implement CRM features epic") — badge de tarefa vencida, alerta de card parado,
relatório de funil, motivo de perda (`PipelineLostReason`), automação criando `Task`, e
recorrência de tarefas — mais bugs remanescentes/regressões colaterais encontrados numa
revisão ponta a ponta do sistema de Tasks (`claude/tasks_tasks/`) já em produção.

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task independente.
Plano de origem: análise técnica de 2026-08-20 (ver histórico de
conversa) — 3 agentes Explore em paralelo (backend das 6 features novas, frontend das 6
features novas, saúde ponta a ponta do sistema de Tasks incluindo confirmação dos 5 fixes de
Tasks da auditoria anterior de 2026-08-16), seguido de verificação manual (leitura direta do
arquivo citado) de todo achado crítico e da maioria dos altos antes de virar task.

## Como esta auditoria foi feita

Mesmo método de `claude/crm_optimizacao_tasks/00-visao-geral.md`: agentes especializados em
paralelo + verificação manual linha a linha antes de transformar um achado em task. Nenhum
item abaixo é especulativo — os críticos e a maioria dos altos foram confirmados lendo o
arquivo real (não só o relato do subagente) antes de escrever esta pasta.

## Status (atualizado em 2026-09-29)

| Tasks | Estado |
|---|---|
| 01, 02, 03 | ✅ Implementadas. Estavam **não commitadas** no working tree da branch `fix/crm-epic-audit-fixes` (revisadas e commitadas em 2026-09-29). |
| 04 | ✅ Implementada — corrigida de passagem pelo commit `78f410567` (PR #41, épico `pipeline_performance_tasks`), não por esta pasta. |
| 05, 06, 07 | ✅ Implementadas em 2026-09-29, com seção `## Resultado` em cada arquivo. |
| 08 a 13 | ✅ Implementadas em 2026-09-30, com seção `## Resultado` em cada arquivo. |
| 14 a 20 | ✅ Implementadas em 2026-10-05, com seção `## Resultado` em cada arquivo. **A lista original (01-20) está concluída.** |
| 21 | ✅ Implementada em 2026-10-06, com seção `## Resultado`. Expôs 7 divergências de Swagger **e um bug de produção** (`GET /pipelines/:id` devolvia 401 para todos, admins inclusive). |
| 22 | ✅ Implementada em 2026-10-06. **Reescrita**: o diagnóstico original (asserções frágeis) estava errado — a suíte rodava contra o banco de **desenvolvimento**. Os specs não precisaram de alteração. |
| 23 | ✅ Implementada em 2026-10-07. **63 chaves** de frontend + **11** de backend traduzidas (a medição original dizia 52 + 9 — ver correção no arquivo). |
| 24 | ✅ Implementada em 2026-10-07. Causa raiz era **outra** (`rails_i18n.enabled_modules = [:pluralization]` no `application.rb`, vindo do upstream) e afetava **todos** os 39 locales não-ingleses, não só o pt_BR. **Pasta concluída.** |

### Tasks acrescentadas durante a implementação

| # | Task | Severidade | Origem |
|---|------|------------|--------|
| [21](21-ligar-skooma-nos-specs-de-request.md) | Ligar o Skooma de verdade nos specs de request | 🟠 Alta | Tasks 11 e 12 |
| [22](22-fix-specs-notificacao-contagem-global.md) | Suíte de specs rodava contra o banco de **desenvolvimento** (`rails_helper` usava `\|\|=` e o container define `RAILS_ENV=development`) | 🟠 Alta | Tasks 10 e 13 |
| [23](23-fix-i18n-pt-br-dominio-crm.md) | Lacunas de tradução `pt_BR` no domínio CRM (63 chaves no frontend + 11 no backend) | 🟠 Alta | Task 20 |
| [24](24-fix-locale-pt-br-nao-carrega-rails-i18n.md) | Locale `pt_BR` não carrega as traduções padrão do Rails — `rails-i18n` traz `pt-BR` (hífen), app usa `pt_BR` (underscore) | 🟠 Alta | Task 23 |

A **21 é a mais consequente das duas**: o `conform_to_definition` do Skooma não é invocado por
nenhum spec do projeto, apesar do `CLAUDE.md` afirmar que a documentação Swagger "é checada em
teste". É a causa raiz das divergências que as tasks 11 e 12 corrigiram — sem ela, o mesmo
problema reaparece no próximo campo novo.

Decisão de produto já tomada para a **task 09** (2026-09-29): *manter a grade, pulando as
ocorrências vencidas* — soma o intervalo a partir do `due_date` original repetidamente até
ultrapassar `Time.current`, preservando a semântica de agenda fixa ("toda segunda-feira") sem
nunca gerar uma ocorrência já nascida vencida. A **task 13** (drift de dia em recorrência
mensal) deve seguir essa mesma âncora.

## Ordem de execução recomendada

| # | Task | Severidade | Área | Depende de |
|---|------|------------|------|------------|
| [01](01-fix-automacao-macro-mover-lost-sem-reason.md) | Automação/Macro "mover pra `lost`" sempre falha silenciosamente | 🔴 Crítico | Backend/Pipeline | — (⚠️ decisão de produto) |
| [02](02-fix-lost-reason-prompt-estado-singleton.md) | `useLostReasonPrompt` — modal zumbi + Promise perdida | 🔴 Crítico | Frontend/Pipeline | — |
| [03](03-fix-recorrencia-task-realtime-broadcast.md) | Recorrência de Task some via broadcast ActionCable | 🔴 Crítico | Backend+Frontend/Tasks | — |
| [04](04-fix-overdue-tasks-count-index-action.md) | `overdue_tasks_count` sempre 0 fora do board + corrompe cache Vuex | 🟠 Alta | Backend+Frontend/Pipeline | — |
| [05](05-fix-create-pipeline-item-lost-reason-id.md) | `create_params` não aceita `pipeline_lost_reason_id` (Swagger documenta) | 🟠 Alta | Backend/Pipeline | 01 |
| [06](06-fix-kanban-card-detail-handle-save-falso-sucesso.md) | `handleSave` reporta sucesso mesmo com move falho/cancelado | 🟠 Alta | Frontend/Pipeline | 02 |
| [07](07-fix-funnel-reports-fetch-duplicado.md) | Fetch duplicado no relatório de funil | 🟠 Alta | Frontend/Pipeline | — |
| [08](08-fix-broadcast-recurrence-interval.md) | Edição isolada de recorrência não propaga em tempo real | 🟠 Alta | Backend/Tasks | 03 |
| [09](09-fix-next-due-date-ancoragem.md) | Recorrência atrasada nunca se recupera (ancoragem de data) | 🟠 Alta | Backend/Tasks | — (⚠️ decisão de produto) |
| [10](10-fix-dedup-notification-primary-actor-type.md) | Dedup de notificação apaga registro legítimo por colisão de ID entre tipos | 🟠 Alta | Backend/Notification | — |
| [11](11-fix-swagger-stale-alert-days.md) | `stale_alert_days` ausente do Swagger | 🟡 Média | Backend/Docs | — |
| [12](12-fix-swagger-overdue-tasks-count.md) | `overdue_tasks_count` ausente do Swagger | 🟡 Média | Backend/Docs | 04 |
| [13](13-fix-recorrencia-mensal-drift-dia.md) | Recorrência mensal: drift do dia em meses curtos | 🟡 Média | Backend/Tasks | 09 |
| [14](14-fix-create-next-occurrence-rescue.md) | `create_next_occurrence` sem tratamento de erro (500 pós-persistência) | 🟡 Média | Backend/Tasks | — |
| [15](15-fix-funnel-reports-try-catch.md) | `fetchReport` sem tratamento de erro de rede | 🟡 Média | Frontend/Pipeline | — |
| [16](16-fix-reagendar-task-cancela-notificacao-enfileirada.md) | Reagendar task não cancela notificação já enfileirada | 🟡 Média | Backend/Tasks | — |
| [17](17-fix-create-task-pipeline-item-titulo-obrigatorio.md) | Automação "criar task" sem título falha silenciosamente | 🟢 Baixa | Backend/Pipeline | — |
| [18](18-fix-automation-task-due-in-days-zero.md) | `due_in_days = 0` tratado como falsy no formulário de automação | 🟢 Baixa | Frontend/Pipeline | — |
| [19](19-fix-claim-trigger-due-tasks-job-atomico.md) | Claim de `TriggerDueTasksJob` não é CAS atômico de verdade | 🟢 Baixa | Backend/Tasks | — |
| [20](20-fix-i18n-pt-br-pipeline-item-stale-settings.md) | i18n `pt_BR` falta `PIPELINE_ITEM_STALE` em `settings.json` | 🟢 Baixa | Frontend/i18n | — |

Tasks 01-03 = **Grupo A** (críticos, bloqueiam ou corrompem dados em produção — priorizar).
Tasks 04-10 = **Grupo B** (altos, bugs funcionais reais). Tasks 11-16 = **Grupo C** (médios,
docs/robustez). Tasks 17-20 = **Grupo D** (baixos, qualquer ordem). Dentro de cada grupo, a
ordem numérica é a ordem de execução recomendada, mas grupos B/C/D podem ser paralelizados
entre si se mais de uma pessoa/sessão for trabalhar simultaneamente — só respeitar as
dependências marcadas na tabela.

## ⚠️ Tasks que exigem decisão de produto antes de codar

- **Task 01**: mudar o comportamento de mover card pra `lost` via automação/macro é uma
  mudança de UX de configuração (nova pergunta obrigatória na automação), não só um fix de
  linha — confirmar com o usuário antes de implementar.
- **Task 09**: ancorar a próxima ocorrência de recorrência em "agora" em vez do `due_date`
  antigo muda a semântica de quando a tarefa recorrente vence — confirmar comportamento
  esperado antes de implementar (afeta também a task 13, que depende dessa decisão).

## Padrões existentes no código que estas tasks devem seguir (não reinventar)

- **Task 01**: mesmo padrão de coleta de parâmetro extra numa ação de automação já usado por
  `AutomationActionCreatePipelineItemTaskInput.vue` (task 09 do épico CRM) + whitelist em
  `AutomationRule#actions_attributes` (`app/models/automation_rule.rb:42-49`).
- **Task 04**: cálculo agregado já correto em `PipelineItemsController#nested_pipeline_index`
  (`app/controllers/api/v1/accounts/pipeline_items_controller.rb:90-93`) — extrair para método
  privado compartilhado com `#index`, não duplicar a query.
- **Task 05**: `update_params` já permite `:pipeline_lost_reason_id`
  (`pipeline_items_controller.rb:124`) — só replicar em `create_params` (linha 114-118).
- **Task 03/08**: `_task.json.jbuilder` já retorna `recurrence_interval`/`recurrence_parent_id`
  corretamente — espelhar em `Task#push_event_data` (`app/models/task.rb:77-90`); para a
  mutation do Vuex, checar se existe padrão de merge parcial em outro módulo (ex.
  `kanban/applyRealtimePipelineItem`) antes de decidir a forma do fix.
- **Task 11/12**: processo de Swagger já documentado no projeto — editar o YAML correto em
  `swagger/definitions/` e rodar `bundle exec rails swagger:build` antes de considerar pronto
  (regra de memória do projeto sobre deploy de endpoints).
- **Task 10**: `Notification::PRIMARY_ACTORS = %w[Conversation Task PipelineItem]`
  (`app/models/notification.rb`) — escopar a query de dedup por `primary_actor_type` do mesmo
  jeito que já é feito em outras queries de `Notification` que filtram por ator.

## Riscos consolidados (ver detalhe em cada task)

1. Task 01 muda o comportamento de uma validação que já está em produção — qualquer automação/
   macro configurada pra mover card pra `lost` está quebrada agora; comunicar isso ao decidir
   prioridade (não é um bug de baixo impacto apesar de exigir decisão de produto).
2. Tasks 03 e 08 tocam o fluxo de tempo real compartilhado por **todos** os eventos de `Task`
   (`created`/`updated`/`completed`/`deleted`) — testar manualmente os 4 eventos depois de
   qualquer mudança em `push_event_data`/`broadcast_relevant_change?`/mutations do Vuex, não só
   o cenário de recorrência.
3. Task 04 mexe numa query que já é agregada corretamente num lugar e ausente em outro —
   validar que a versão unificada continua 1 query por listagem, não reintroduzir N+1 (mesma
   classe de bug já corrigida duas vezes nesse módulo pela auditoria de 2026-08-16, tasks 02 e
   03 de `crm_optimizacao_tasks/`).
4. Tasks 09/13 (recorrência) mudam uma regra de negócio ativa em produção desde
   2026-08-19 — pode haver tarefas recorrentes já criadas com o comportamento antigo; decidir
   se precisa de dado de migração/backfill ou se o novo comportamento só vale daqui pra frente.
5. Nenhuma das áreas tocadas (Pipeline, Task, Notification, Report) tem hoje extensão conhecida
   em `enterprise/` — confirmar rapidamente por task (skill `sincronizar-enterprise`) antes de
   fechar cada uma.
6. Tasks 01, 03, 04, 08, 09, 10 tocam código sem cobertura de teste automatizado hoje — testar
   manualmente no Docker local antes de considerar concluído (não escrever specs a menos que
   pedido explicitamente, regra do `AGENTS.md`).
