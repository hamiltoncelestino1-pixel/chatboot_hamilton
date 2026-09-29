# Task 13 — Fix: recorrência mensal — drift do dia do mês em meses curtos

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).
Depende da decisão de produto tomada na task 09.

## Objetivo

`app/models/task.rb:132`: `when 'monthly' then due_date + 1.month`.

Task com `due_date` em 31/jan e `recurrence_interval: monthly`. Ao completar, `due_date +
1.month` vira 28/fev (comportamento padrão de clamping do ActiveSupport, sem erro). Ao
completar essa segunda ocorrência, a próxima soma `+1.month` a partir de 28/fev, gerando
28/mar — não 31/mar. O "dia 31" nunca mais volta em nenhuma ocorrência futura da cadeia, sem
nenhum aviso pro usuário. `swagger/definitions/request/task/create_payload.yml:22-27` só diz
"due the corresponding period after this task's due_date", sem alertar sobre esse drift.

## O que corrigir

Depende de qual semântica foi decidida na task 09:
- Se a task 09 mudou a ancoragem pra "agora"/conclusão, o drift de dia-do-mês ainda pode
  ocorrer (é inerente a somar meses em datas perto do fim do mês), então o mínimo aqui é
  **documentar o comportamento** no Swagger (`create_payload.yml`) e, se fizer sentido pro
  produto, preservar o "dia alvo" original guardando-o separadamente e recalculando a data de
  cada ocorrência a partir desse dia-alvo (em vez de encadear `due_date + 1.month` sobre o
  valor já clampado da ocorrência anterior) — evita o drift permanente, mesmo que ocasionalmente
  caia em fim de mês.
- Confirmar com o usuário se vale o esforço de preservar o dia-alvo (mais robusto, mais
  código) ou se só documentar o comportamento atual já é suficiente (mais simples).

## Testes

Testar manualmente: criar task mensal com `due_date` em 31 de um mês, completar 3-4 vezes
seguidas, confirmar que o comportamento (preservação do dia-alvo ou drift documentado) é o
esperado segundo a decisão tomada.

## Critério de pronto

- Comportamento de recorrência mensal em meses curtos é o decidido com o usuário (preservado
  ou documentado).
- Swagger de `Task` reflete o comportamento real.
- `bundle exec rubocop -a` limpo nos arquivos tocados.
