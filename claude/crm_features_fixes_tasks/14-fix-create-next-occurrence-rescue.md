# Task 14 — Fix: `create_next_occurrence` sem tratamento de erro (500 pós-persistência)

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/models/task.rb:63-64,113-126`:

```ruby
after_update_commit :create_next_occurrence, if: -> { saved_change_to_completed_at? && recurrence_interval.present? }
# ...
def create_next_occurrence
  return if completed_at.blank?

  account.tasks.create!(
    title: title,
    due_date: next_due_date,
    assignee_id: assignee_id,
    contact_id: contact_id,
    conversation_id: conversation_id,
    pipeline_item_id: pipeline_item_id,
    recurrence_interval: recurrence_interval,
    recurrence_parent_id: id
  )
end
```

Roda em `after_update_commit`, sem `rescue`. `pipeline_item_must_belong_to_contact`
(`task.rb:100-104`) valida a nova task; se `pipeline_item_id` copiado apontar pra um card
apagado entre o carregamento da task original em memória e o `complete` (o `dependent:
:nullify` do `PipelineItem` roda um `UPDATE` direto no banco, sem tocar a instância Ruby já
carregada), a validação falha, `create!` lança `RecordInvalid` **dentro do callback**, e a
exceção propaga pra fora do `update!` que o controller já tinha executado com sucesso.

**Efeito**: `app/controllers/api/v1/accounts/tasks_controller.rb#complete` já persistiu a
conclusão da task original (o `update!` comitou, é isso que dispara o callback), mas o
response do controller estoura 500 por causa de uma falha na criação da *próxima* ocorrência —
o agente vê um erro numa ação que, do ponto de vista de dados, já funcionou.

## O que corrigir

Envolver `create_next_occurrence` num tratamento de erro que não deixe a exceção propagar pra
fora do fluxo de conclusão da task original — seguir o mesmo padrão de resiliência já usado
noutros callbacks/services do projeto que reportam pro `ChatwootExceptionTracker` em vez de
estourar (ex. `rescue StandardError => e; ChatwootExceptionTracker.new(exception: e).capture_exception`),
garantindo que a resposta da action `complete` continue `200`/sucesso mesmo se a próxima
ocorrência não puder ser criada. Se fizer sentido pro produto, considerar também notificar o
assignee de alguma forma que a cadeia de recorrência foi interrompida (fora do escopo mínimo,
perguntar se é necessário).

## Testes

Testar manualmente: completar uma task recorrente cujo `pipeline_item_id` aponte pra um card
já apagado (simular deletando o card antes de completar a task) — a conclusão da task deve
retornar sucesso (a task original fica marcada como completa), mesmo que a próxima ocorrência
não seja criada.

## Critério de pronto

- Completar uma task recorrente nunca retorna 500 por causa de falha na criação da próxima
  ocorrência.
- Falha na criação da próxima ocorrência é reportada (Sentry/log), não silenciosamente
  ignorada nem exposta como erro pro usuário numa ação que já teve sucesso.
- `bundle exec rubocop -a` limpo no arquivo tocado.
