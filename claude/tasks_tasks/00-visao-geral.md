# Visão Geral — Tarefas (Tasks) para Pipeline, Conversa e Contato

## Objetivo

Adicionar uma entidade nova, `Task`, que o usuário cria a partir de três pontos de entrada —
card de pipeline, conversa, e perfil do contato — com um título e uma data/hora de vencimento
(`due_date`). Quando a tarefa vence, o responsável (`assignee`) recebe uma notificação pelos
canais já existentes do Chatwoot: caixa de entrada (sempre ativa) e, opcionalmente, email/push
(configurável numa nova entrada na tela de preferências de notificação do perfil).

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task de implementação
independente, na ordem recomendada de execução. Nenhuma task aqui foi implementada ainda — são
especificações prontas para pegar e codar. Plano de origem:
`claude/tasks_tasks/../..` (ver histórico de conversa — análise de viabilidade de 2026-08-13).

## Ordem de execução

| # | Task | Depende de |
|---|------|------------|
| [01](01-schema-model-task.md) | Backend: migration + model `Task` | — |
| [02](02-policy-controller-swagger.md) | Backend: policy, controller, rotas, views, Swagger | 01 |
| [03](03-integracao-notification.md) | Backend: integração com `Notification`/`NotificationSetting` | 01 |
| [04](04-job-periodico-vencimento.md) | Backend: job periódico de vencimento + disparo de notificação | 01, 03 |
| [05](05-tempo-real-actioncable.md) | Backend: eventos Wisper + broadcast ActionCable de tarefas | 01 |
| [06](06-frontend-api-store-realtime.md) | Frontend: API client + store Vuex + handlers de tempo real | 02, 05 |
| [07](07-frontend-componente-compartilhado.md) | Frontend: componentes `Tasks/` compartilhados (lista/item/form) | 06 |
| [08](08-frontend-integracao-pipeline-card.md) | Frontend: seção "Tarefas" no card de pipeline | 07 |
| [09](09-frontend-integracao-sidebar-conversa.md) | Frontend: seção "Tarefas" na sidebar da conversa | 07 |
| [10](10-frontend-integracao-perfil-contato.md) | Frontend: aba "Tarefas" no perfil do contato | 07 |
| [11](11-frontend-preferencias-notificacao.md) | Frontend: entrada `task_due` nas preferências de notificação | 03 |
| [12](12-i18n.md) | i18n: `tasks.json` + strings de push notification | 07, 08, 09, 10 |

Tasks 01-05 = **Grupo A** (backend/dados). Tasks 06-10 = **Grupo B** (frontend/UI). Task 11 =
**Grupo C** (preferências). Task 12 fecha tudo (i18n das telas construídas nos grupos B/C).

## Decisões de produto já confirmadas com o usuário

- Notificação de **caixa de entrada (sino) é sempre ativa** para tarefa vencida — não é
  configurável. A nova entrada na tela de preferências do perfil controla só email/push,
  reaproveitando a infra existente de `NotificationSetting` sem estendê-la.
- **Só o responsável (`assignee`) da tarefa é notificado** quando ela vence — sem notificar
  equipe do pipeline ou participantes da conversa.
- Escopo desta primeira versão: tarefa única (sem recorrência), um responsável só, sem ação de
  automação/macro criando tarefas automaticamente (fica como extensão futura, não é bloqueio).
- Feature é **core** (`app/`), não `enterprise/` — não é licenciada, mesmo espírito do
  Pipeline/Kanban que já é core neste fork.

## Padrões existentes no código que estas tasks devem seguir (não reinventar)

- **Forma do model** — `PipelineItem` (`app/models/pipeline_item.rb:40-53`) já resolve o mesmo
  problema de "pertence a vários contextos": `belongs_to :contact` obrigatório, `belongs_to
  :conversation, optional: true`. `Task` copia essa forma com uma FK opcional a mais
  (`pipeline_item_id`). **Não usar polimorfismo** — não existe hoje nenhum precedente de
  polimorfismo relacionando PipelineItem+Conversation+Contact ao mesmo tempo (o único
  polimórfico real do projeto, `Notification#primary_actor`, só cobre `Conversation`/`Message`)
  e inventar um `taskable_type` novo seria infra nova sem padrão local para copiar.
- **Notificação de vencimento** — o precedente é `SlaEvent#create_notifications`
  (`enterprise/app/models/sla_event.rb:64-86`): chama `NotificationBuilder.new(...).perform`
  diretamente a partir de um callback/job, **sem** passar pelo Wisper para o "vencimento" em si
  (Wisper aqui é só para tempo real do card/sidebar). `Task` copia esse fluxo.
- **Job periódico de varredura por data** — `TriggerScheduledItemsJob`
  (`app/jobs/trigger_scheduled_items_job.rb`) sempre filtra com janela
  `campo_data: 3.days.ago..Time.current` (nunca só `<=`), usa `find_each(batch_size: 100)`, e
  enfileira **um job dedicado por registro**. Não existe nenhum uso de `.perform_at`/`.perform_in`
  no projeto — todo agendamento é polling + janela de tempo; seguir essa convenção.
- **`NOTIFICATION_TYPES` ganha email/push de graça** — `NotificationSetting`
  (`app/models/notification_setting.rb:30-31`) gera `email_flags`/`push_flags` dinamicamente a
  partir de `Notification::NOTIFICATION_TYPES` via FlagShihTzu. Adicionar `task_due` ao enum já
  basta, sem migração.
- **Defaults de notificação são opt-in** — `AccountUser#create_notification_setting`
  (`app/models/account_user.rb:45-50`) só liga `email_conversation_assignment`/
  `push_conversation_assignment` por padrão; todo o resto (incluindo `task_due`) nasce
  desligado até o usuário ativar manualmente na tela de preferências. **Não** adicionar
  `task_due` a essa lista de defaults — mantém o mesmo comportamento dos outros 7 tipos.
- **Sub-recurso de API com filtro por query param** — `PipelineItemsController#index` já filtra
  por `contact_id`/`conversation_id` via query params (`app/controllers/api/v1/accounts/pipeline_items_controller.rb:19-20`).
  `TasksController` copia essa forma (`?contact_id=`/`?conversation_id=`/`?pipeline_item_id=`)
  em vez de virar 3 rotas aninhadas diferentes.
- **Store dedicada indexada por parent** — `store/modules/contactNotes.js` (records indexados
  por `contactId`) é o modelo mais simples; `kanban/getItemsForContact`/`getItemsForConversation`
  (`store/modules/kanban/getters.js:101-107`) mostram o padrão de filtrar um único state
  compartilhado por FK, que é o que `store/modules/tasks/` deve seguir (mais simples de manter
  sincronizado nos 3 pontos de entrada do que 3 states separados).
- **Seção nova na sidebar da conversa** — `ConversationOpportunities.vue` +
  `ContactPanel.vue` (`app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue:241-256`)
  é o componente e o `AccordionItem` mais próximos do que se quer construir.
- **Seção nova no perfil do contato** — `ContactManageView.vue`
  (`app/javascript/dashboard/routes/dashboard/contacts/pages/ContactManageView.vue`) usa abas
  fixas (`CONTACT_TABS_OPTIONS` + `activeTab`), **não** o sistema de ordem arrastável da
  sidebar de conversa — `ContactTasks.vue` entra como mais uma aba, não um `AccordionItem`.
- **Seção nova no card do pipeline** — `AccordionItem` de atributos customizados em
  `KanbanCardDetail.vue` (linha ~418) é o padrão de "seção expansível dentro do card".
- **Tempo real** — `lib/events/types.rb` + `ActionCableListener`
  (`app/listeners/action_cable_listener.rb:176-188`, caso `pipeline_item_created/updated`) +
  `helper/actionCable.js:38-39,204-206` (`onPipelineItemChanged` → `kanban/applyRealtimePipelineItem`)
  é o padrão fim-a-fim a copiar para os 4 eventos de `Task`.
