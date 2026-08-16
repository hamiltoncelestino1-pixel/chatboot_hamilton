# Task 09 — Automação de pipeline cria `Task`

Feature 1. Sem dependências, padrão mais direto do épico.

## Objetivo

Adicionar uma ação nova de automação de pipeline: "criar tarefa" — quando um gatilho nativo
de pipeline dispara (card criado / card mudou de estágio), cria uma `Task` vinculada ao
card, com título e prazo (em dias a partir de agora) configuráveis na regra.

## Decisão a confirmar no início da implementação

Escopo: só gatilhos nativos de pipeline (`pipeline_item_created`/`pipeline_item_stage_changed`,
via `AutomationRules::PipelineActionService`), ou também gatilhos de conversa (via
`AutomationRules::ActionService`, resolvendo o pipeline item a partir do contato)? Isso muda
quantos arquivos a task toca (dobra o trabalho de frontend/backend se incluir os dois).
Recomendação: começar só pelos gatilhos nativos de pipeline (menor escopo, cobre o caso de
uso mais comum — "card entrou no estágio X, criar tarefa de follow-up"), estender pra
conversa depois se for pedido.

## Estado atual (confirmado por leitura de código)

- `AutomationRules::PipelineActionService#perform`
  (`app/services/automation_rules/pipeline_action_service.rb:18-33`) faz
  `send(action[:action_name], action[:action_params])` — dispatch dinâmico, cada ação nova
  é só mais um método privado.
- `AutomationRule#actions_attributes` (`app/models/automation_rule.rb:42-49`) é a whitelist
  que valida `action_name` no save da regra — **sem entrada aqui, a regra é rejeitada**.
- `app/services/concerns/pipeline_item_actions.rb` é o módulo compartilhado de primitivas de
  mutação de `PipelineItem`, usado por automação e macro.
- `TasksController#create` (`app/controllers/api/v1/accounts/tasks_controller.rb:15-19`) é
  o padrão de criação de `Task` a copiar (`Current.account.tasks.new(...)` + fallback de
  assignee).

## O que criar

1. `app/models/automation_rule.rb:42-49` — adicionar `create_pipeline_item_task` em
   `actions_attributes`.
2. `app/services/concerns/pipeline_item_actions.rb` — novo método público:
   ```ruby
   def create_task_for_pipeline_item(pipeline_item, attrs)
     pipeline_item.account.tasks.create!(
       title: attrs[:title],
       due_date: attrs[:due_in_days].to_i.days.from_now,
       assignee_id: attrs[:assignee_id].presence || pipeline_item.assignee_id,
       contact_id: pipeline_item.contact_id,
       pipeline_item_id: pipeline_item.id
     )
   end
   ```
   `due_date` **não** parseia string livre ("+2 dias") — não existe parser desse tipo no
   projeto; o parâmetro do frontend já vem como inteiro (`due_in_days`). Se o card não tiver
   assignee e o parâmetro também não vier preenchido, `create!` falha — isso já é engolido
   pelo `rescue StandardError` do `perform` da automação (não derruba a regra inteira, só
   loga via `ChatwootExceptionTracker`), mas considerar logar explicitamente esse caso
   (padrão de `log_invalid_team`/`log_invalid_target_stage` já usado no mesmo arquivo) em
   vez de deixar só no Sentry.
3. `app/services/automation_rules/pipeline_action_service.rb` — novo método privado:
   ```ruby
   def create_pipeline_item_task(params)
     params = params[0]
     create_task_for_pipeline_item(@pipeline_item, params)
   end
   ```
4. Frontend:
   - `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` —
     entrada nova em `AUTOMATION_ACTION_TYPES` (`inputType: 'pipeline_create_task'`) +
     entrada em `actions:` de `pipeline_item_created`/`pipeline_item_stage_changed`.
   - Componente novo `AutomationActionCreatePipelineItemTaskInput.vue`, espelhando
     `AutomationActionCreatePipelineItemInput.vue` (input de título + input numérico de
     dias até o vencimento, em vez do bloco `title/value/notes`).
   - `AutomationActionInput.vue` — import + branch de template
     (`v-if="inputType === 'pipeline_create_task'"`) + incluir em `isVerticalLayout` se o
     layout for vertical.
   - i18n em `automation.json` (en + pt_BR — domínio já na exceção documentada no
     `CLAUDE.md`).

## Testes

Testar manualmente no Docker local: criar uma automação com gatilho "card entrou no
estágio X" + ação "criar tarefa" (título fixo, 2 dias de prazo), mover um card pro estágio
configurado, confirmar que a `Task` é criada com `due_date` correto e assignee correto
(tanto com `assignee_id` explícito na regra quanto usando o fallback do assignee do card).

## Critério de pronto

- Ação nova aparece no dropdown de automação de pipeline e salva corretamente na regra.
- Task criada com título/prazo/assignee corretos ao disparar a automação.
- Falha de criação (ex. sem assignee disponível) não derruba a automação inteira.
- i18n en + pt_BR sincronizados (domínio automation).
- `bundle exec rubocop -a` / `pnpm eslint:fix` limpos nos arquivos tocados.
