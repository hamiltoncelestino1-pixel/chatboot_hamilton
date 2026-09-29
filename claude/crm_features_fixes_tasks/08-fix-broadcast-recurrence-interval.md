# Task 08 — Fix: edição isolada de recorrência não propaga em tempo real

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).
Depende da task 03 (mesma área: broadcast de mudanças de `Task`).

## Objetivo

`app/models/task.rb:140-142`:

```ruby
def broadcast_relevant_change?
  saved_change_to_due_date? || saved_change_to_title? || saved_change_to_assignee_id?
end
```

`recurrence_interval` é editável via `update_params`
(`app/controllers/api/v1/accounts/tasks_controller.rb:52`) mas não está nesse predicado, que
controla `after_update_commit :dispatch_updated_event, if: :broadcast_relevant_change?`
(`task.rb:63`).

**Efeito**: agente muda só o dropdown "Repeat" de uma task existente (de semanal pra mensal,
ou desliga a recorrência), sem tocar título/data/assignee no mesmo save —
`dispatch_updated_event` nunca dispara, então outros clientes conectados na conta continuam
vendo o `recurrence_interval` antigo até um refetch manual (reabrir o painel da task).
Combinado com o bug da task 03, a sincronização em tempo real de recorrência está quebrada nos
dois sentidos: nem propaga quando muda sozinha, nem preserva o valor quando propaga junto com
outro campo.

## O que corrigir

Adicionar `saved_change_to_recurrence_interval?` ao predicado `broadcast_relevant_change?`.

## Testes

Testar manualmente com duas abas/sessões na mesma conta: editar só o campo "Repeat" de uma
task existente numa aba — a outra aba deve refletir a mudança sem precisar de refresh manual
(confirmar que o evento `task.updated` chega via ActionCable com o `recurrence_interval` novo,
dependendo também do fix da task 03 estar aplicado em `push_event_data`).

## Critério de pronto

- Mudar só a recorrência de uma task dispara o evento de tempo real `task.updated`.
- Outros clientes conectados recebem o valor atualizado sem refetch manual.
- `bundle exec rubocop -a` limpo no arquivo tocado.
