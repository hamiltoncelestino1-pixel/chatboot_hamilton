# Task 28 — Backend: corrigir `MacrosController#execute` (validar `macro_type`)

Parte do Grupo E ([visão geral](00-visao-geral.md)). Sem dependência técnica das outras tasks
do grupo, mas faz mais sentido implementar depois das tasks 26/27 (é quando o bug fica mais
perigoso, com ambos os tipos de macro ganhando ações plausíveis nos dois domínios).

## Objetivo

Fechar um bug latente encontrado na investigação: hoje `MacrosController#execute`
(`app/controllers/api/v1/accounts/macros_controller.rb:51-59`) decide qual `ExecutionService`
rodar **pela presença do parâmetro do request**, não pelo `macro.macro_type` salvo:

```ruby
if params[:pipeline_item_ids].present?
  ::MacrosPipelineExecutionJob.perform_later(@macro, pipeline_item_ids: authorized_pipeline_item_ids, user: Current.user)
else
  ::MacrosExecutionJob.perform_later(@macro, conversation_ids: params[:conversation_ids], user: Current.user)
end
```

Nada impede hoje enviar `pipeline_item_ids` para um macro `macro_type: conversation`, ou
`conversation_ids` (implícito, via `else`) para um macro `macro_type: pipeline_item`. O
resultado é engolido silenciosamente pelo `rescue StandardError` por-ação de cada
`ExecutionService` (as ações do tipo errado simplesmente não existem como método na classe
errada, então toda ação falha silenciosa, reportada só no `ChatwootExceptionTracker`, sem
feedback nenhum pro usuário).

## Mudança

```ruby
def execute
  case @macro.macro_type
  when 'pipeline_item'
    return render json: { error: I18n.t('macros.execute.pipeline_item_ids_required') }, status: :unprocessable_entity if params[:pipeline_item_ids].blank?

    ::MacrosPipelineExecutionJob.perform_later(@macro, pipeline_item_ids: authorized_pipeline_item_ids, user: Current.user)
  else
    return render json: { error: I18n.t('macros.execute.conversation_ids_required') }, status: :unprocessable_entity if params[:conversation_ids].blank?

    ::MacrosExecutionJob.perform_later(@macro, conversation_ids: params[:conversation_ids], user: Current.user)
  end
  head :ok
end
```

Ajustar a mensagem de erro exata / chave i18n de backend conforme o padrão já usado em outros
`render json: { error: ... }` deste controller (conferir se já existe uma convenção local antes
de inventar uma chave nova). O importante é: **request com o par errado (`macro_type` vs id
list) retorna 422 explícito**, não silenciosamente enfileira um job que vai falhar ação por
ação.

## Frontend

Conferir se o frontend (`KanbanRunMacroMenu.vue`, `conversation/Macros/List.vue`) já garante
hoje que só manda o parâmetro certo (a filtragem por `macro.macro_type === 'pipeline_item'`/
`'conversation'`, task 14) — se sim, essa mudança de backend é só uma rede de segurança contra
uso indevido da API diretamente (Postman, integração externa), não deve mudar nenhum
comportamento observável no uso normal pela UI.

## Testes

`spec/controllers/api/v1/accounts/macros_controller_spec.rb` (existente, estender) —
- macro `pipeline_item` + `pipeline_item_ids` → enfileira `MacrosPipelineExecutionJob` (já
  coberto, confirmar que continua passando).
- macro `pipeline_item` + `conversation_ids` (ou nenhum id) → 422, nenhum job enfileirado.
- macro `conversation` + `conversation_ids` → enfileira `MacrosExecutionJob` (comportamento
  atual, confirmar que continua passando).
- macro `conversation` + `pipeline_item_ids` → 422, nenhum job enfileirado.

## Critério de pronto

- Combinação errada de `macro_type` + parâmetro de execução retorna 422 explícito.
- Combinações corretas continuam funcionando exatamente como antes (specs existentes verdes).
- `bundle exec rubocop -a` limpo.
