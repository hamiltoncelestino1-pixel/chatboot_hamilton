# Task 03 — Fix: recorrência de Task some silenciosamente via broadcast ActionCable

Severidade: 🔴 Crítico. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/models/task.rb:77-90` (`push_event_data`, usado pelo broadcast em tempo real):

```ruby
def push_event_data
  {
    id: id,
    title: title,
    due_date: due_date.to_i,
    completed_at: completed_at&.to_i,
    created_at: created_at.to_i,
    updated_at: updated_at.to_i,
    contact_id: contact_id,
    conversation_id: conversation_id,
    pipeline_item_id: pipeline_item_id,
    assignee: assignee.push_event_data
  }
end
```

Não inclui `recurrence_interval` nem `recurrence_parent_id`. Esse hash é consumido por
`app/listeners/action_cable_listener.rb:194,201,208` para os broadcasts de `TASK_CREATED`,
`TASK_UPDATED` e `TASK_COMPLETED` — todo cliente conectado na conta recebe esse payload
incompleto, **inclusive o próprio agente que disparou a ação**.

Em contraste, a resposta REST (`app/views/api/v1/models/_task.json.jbuilder:8-9`) inclui os
dois campos corretamente.

No frontend, `app/javascript/dashboard/store/modules/tasks/mutations.js` (`SET_TASK_DATA`) faz
**replace total** do objeto da task no state, não merge parcial.

**Efeito**: agente completa uma task recorrente semanal pela UI. A resposta REST da chamada de
`complete` (com `recurrence_interval` correto) grava no Vuex. Milissegundos depois chega o
broadcast `task.completed` (e o `task.created` da nova ocorrência) via ActionCable — esse
payload não tem `recurrence_interval`, e o replace total zera o campo no store. Se
`TaskFormModal.vue:28` (`recurrenceInterval.value = props.task?.recurrence_interval || ''`) for
aberto depois para essa task (ou para a nova ocorrência, que só chegou via realtime), o campo
aparece como "Does not repeat". Salvando sem tocar no dropdown, `TaskFormModal.vue` manda
`recurrence_interval: null` de volta pro backend — **desligando a recorrência de verdade no
banco**, silenciosamente, sem nenhuma ação intencional do usuário.

## O que corrigir

1. `Task#push_event_data` (`app/models/task.rb:77-90`) — incluir `recurrence_interval:
   recurrence_interval` e `recurrence_parent_id: recurrence_parent_id`, espelhando exatamente
   o que `_task.json.jbuilder` já retorna.
2. Frontend: revisar a mutation `SET_TASK_DATA`
   (`app/javascript/dashboard/store/modules/tasks/mutations.js`) — mesmo com o fix do item 1,
   qualquer payload realtime futuro que não inclua 100% dos campos vai continuar sujeito ao
   mesmo tipo de bug enquanto a mutation fizer replace total. Avaliar mudar para merge parcial
   (`{ ...state.items[task.id], ...task }`) em vez de substituição completa — checar se existe
   um padrão de merge parcial já usado em outro módulo Vuex do projeto (ex.
   `kanban/applyRealtimePipelineItem`) antes de decidir a forma exata.

## Testes

Testar manualmente no Docker local com duas abas/sessões abertas na mesma conta:
- Completar uma task recorrente semanal na aba A — na aba B (e na própria aba A depois de
  reabrir o `TaskFormModal`), confirmar que a nova ocorrência criada mostra `recurrence_interval:
  weekly` corretamente, não "Does not repeat".
- Reabrir e salvar o formulário da nova ocorrência sem tocar no campo "Repeat" — confirmar que
  a recorrência continua ativa no banco depois do save (não foi desligada por engano).
- Confirmar que os outros 3 eventos de Task (`created`, `completed` sem recorrência,
  `deleted`) continuam funcionando sem regressão.

## Critério de pronto

- `push_event_data` inclui todos os campos que a resposta REST já inclui.
- Editar/salvar uma task recebida via realtime não apaga `recurrence_interval` por engano.
- Os 4 tipos de evento de Task (`created`/`updated`/`completed`/`deleted`) continuam
  funcionando sem regressão.
- `bundle exec rubocop -a` e `pnpm eslint:fix` limpos nos arquivos tocados.
