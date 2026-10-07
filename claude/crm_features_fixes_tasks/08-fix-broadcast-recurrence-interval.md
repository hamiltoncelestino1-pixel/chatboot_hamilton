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

## Decisão e resultado (2026-09-30)

`saved_change_to_recurrence_interval?` acrescentado a `broadcast_relevant_change?`
(`app/models/task.rb`), quebrado em duas linhas por causa do `Layout/LineLength Max: 150`.

**Decisão registrada — não colapsar para `saved_changes?`.** Com esta mudança o predicado passa a
cobrir os 4 campos que `update_params` permite (`tasks_controller.rb:52`: `title`, `due_date`,
`assignee_id`, `recurrence_interval`), o que tornaria tentador simplificar para um
`saved_changes?` genérico. Deliberadamente mantida a lista explícita, com comentário no código
explicando: `completed_at` tem evento próprio (`dispatch_completed_event`, `task.rb:62`) e um
predicado genérico passaria a transmitir escritas internas de coluna que ninguém quis propagar.

**Verificação empírica** (`rails runner` no Docker local, task 24, cada caso em transação com
`ActiveRecord::Rollback`). Não há **nenhum** spec de `Task` no projeto (`find spec -iname
"*task*"` só retorna specs de `Captain::BaseTaskService`), então esta é a única evidência
automatizável:

| Mudança isolada | `broadcast_relevant_change?` | Leitura |
|---|---|---|
| só `recurrence_interval` | `true` | é a correção — antes era `false` |
| só `title` | `true` | não-regressão do que já funcionava |
| só `reminder_sent_at` | `false` | **o mais importante**: prova que o predicado avalia a cláusula nova de verdade e que não foi alargado demais |

O terceiro caso é o que valida a decisão acima: com `saved_changes?` ele teria dado `true`.
Também descarta a hipótese de o método estar apenas retornando sempre verdadeiro, e um nome de
método errado teria levantado `NoMethodError` no primeiro caso — daí não ter sido necessário
reverter a mudança para provar o comportamento anterior.

Nada persistido no banco de dev (`recurrence_interval` da task 24 segue `nil`).

**Rubocop:** `app/models/task.rb` — 1 arquivo, nenhuma ofensa (incluindo `Layout/EndOfLine`,
conferido de propósito: este arquivo estava entre os 4 que precisaram de normalização CRLF→LF no
commit das tasks 01-03).

**Par com a task 03:** a 03 fez `push_event_data` carregar `recurrence_interval` e
`recurrence_parent_id`; esta faz o evento ser disparado quando só a recorrência muda. Antes das
duas a sincronização estava quebrada nos dois sentidos — não propagava sozinha e, quando
propagava junto com outro campo, apagava o valor no cliente. O teste manual só faz sentido com
as duas aplicadas.
