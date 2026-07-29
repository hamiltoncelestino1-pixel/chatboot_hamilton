# Task 03 — Reforçar a regra de card único em todos os pontos de criação/edição

Parte do Grupo A ([visão geral](00-visao-geral.md)). Depende das tasks 01 e 02 (validação +
dados já mesclados). Esta task é sobretudo de **verificação e tratamento de erro**, não de
nova lógica de negócio — a validação já existe no model (task 01) e vale para qualquer
caminho que chame `.save!`/`.update!` num `PipelineItem`.

## Objetivo

Confirmar e cobrir com teste que a regra "1 card por contato por pipeline" é respeitada (com
erro amigável, não um 500) em **todos** os lugares que criam ou movem cards — não só o
controller principal.

## 1. `PipelineItemsController#create`/`#update`

**Já funciona sem mudança de código**: verificado que `RequestExceptionHandler` (incluído em
`application_controller.rb`) já tem `rescue_from ActiveRecord::RecordInvalid` global — como
`@item.save!`/`@item.update!` (`app/controllers/api/v1/accounts/pipeline_items_controller.rb`)
levantam `ActiveRecord::RecordInvalid` quando a validação da task 01 falha, a resposta já sai
como 422 automaticamente. Esta subtask é só **adicionar o teste** que confirma isso (ver
seção de testes abaixo) — não mexer no controller a menos que o teste revele um problema
inesperado.

## 2. `Pipelines::ExportItemService`

Em `app/services/pipelines/export_item_service.rb`, o método `perform` chama
`pipeline_item.update!(pipeline_stage_id: ..., ...)` (linha ~11-15) — ao mudar
`pipeline_stage_id` para um stage de outro pipeline, o callback `before_validation` da task 01
recalcula `pipeline_id`, e se o contato já tiver um card nesse pipeline de destino, o
`update!` levanta `ActiveRecord::RecordInvalid` — que o controller
(`PipelineItemsController#export`) precisa deixar propagar corretamente para o
`rescue_from` global (o `rescue_from` específico de `SamePipelineError`/
`InvalidTargetStageError` já existe nesse controller nas linhas 5-8; confirmar que não
interfere/engole o `RecordInvalid`, que deve continuar caindo no rescue global).

- Adicionar exemplo em `spec/services/pipelines/export_item_service_spec.rb` (arquivo já
  existe): "levanta `ActiveRecord::RecordInvalid` quando o contato já tem um card no pipeline
  de destino".

## 3. Novas ações de automação/macro (tasks 04 e 06)

Documentar explicitamente (não implementar aqui, é responsabilidade das tasks 04/06): a nova
ação `create_pipeline_item` deve criar via `Current.account.pipeline_items.new(...).save!` —
herda a validação automaticamente. Se falhar por duplicidade, a exceção já é pega pelo rescue
por-ação existente em `AutomationRules::ActionService#perform`/`Macros::ExecutionService#perform`
— a regra/macro não deve crashar, só pular aquela ação específica (comportamento já existente
no código, não precisa de tratamento extra).

## 4. Frontend — `AddItemModal.vue`

Em `app/javascript/dashboard/routes/dashboard/kanban/components/AddItemModal.vue`:

- Envolver o dispatch de `kanban/createItem` em try/catch.
- Capturar o corpo do erro 422 (verificar exatamente qual chave a resposta usa — `error`,
  `message` ou `errors`, conferindo o formato de `render_record_invalid` em
  `app/controllers/concerns/request_exception_handler.rb`) e mostrar via o mecanismo de
  toast/alert já usado no arquivo para outras falhas de validação (ex. falha ao criar
  contato) — mirror do padrão já existente, não inventar um novo componente de erro.

## 5. Outros pontos de entrada de criação de card

- `app/javascript/dashboard/components-next/Conversation/ConversationOpportunities.vue`
- `app/javascript/dashboard/components-next/Contacts/ContactsSidebar/ContactOpportunities.vue`

Ambos abrem `AddItemModal.vue` como o formulário real de criação — confirmar (lendo o código)
que não têm um caminho de submit próprio que bypassa o modal; se o tratamento de erro for
corrigido centralmente no modal (item 4), estes dois herdam o comportamento sem mudança
adicional. Só documentar a confirmação, não duplicar código de tratamento de erro aqui.

## Testes

- `spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` — novo exemplo: `POST
  create` para um contato que já tem card naquele pipeline → espera 422 com a mensagem
  específica da task 01.
- `spec/services/pipelines/export_item_service_spec.rb` — novo exemplo conforme item 2 acima.
- QA manual: tentar criar card duplicado pela UI em cada um dos 3 pontos de entrada
  (Kanban, conversa, contato) e confirmar que a mensagem de erro aparece de forma legível
  (não um erro genérico/estourado no console).

## Critério de pronto

- Os 2 novos exemplos de spec passando.
- QA manual dos 3 pontos de entrada de criação de card confirmando a mensagem de erro visível.
