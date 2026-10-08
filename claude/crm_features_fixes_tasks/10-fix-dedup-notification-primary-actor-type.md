# Task 10 — Fix: dedup de notificação apaga registro legítimo por colisão de ID entre tipos

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/jobs/notification/remove_duplicate_notification_job.rb:11`:

```ruby
Notification.where(user_id: user_id, primary_actor_id: primary_actor_id)
```

Esse job pré-existente assumia implicitamente que `primary_actor_id` sozinho já identificava a
origem de uma notificação — verdade só enquanto `Notification::PRIMARY_ACTORS` continha
apenas `Conversation`. Hoje `PRIMARY_ACTORS = %w[Conversation Task PipelineItem]`
(`app/models/notification.rb`), e `Task`, `PipelineItem` e `Conversation` têm sequences de ID
independentes — o mesmo número de ID pode existir simultaneamente nas 3 tabelas.

**Cenário concreto**: usuário tem uma notificação vinculada a `Conversation#100`. Depois,
`Task#100` (mesmo ID, entidade completamente diferente) vence e gera uma notificação
`task_due` pro mesmo usuário. O job trata como duplicata (mesmo `user_id` + mesmo
`primary_actor_id`, ignorando o tipo) e destrói a notificação mais antiga — perda silenciosa de
uma notificação de conversa legítima, por pura coincidência numérica de ID.

Este arquivo não foi tocado nem pelo épico de Tasks original (`claude/tasks_tasks/`) nem pela
auditoria de 2026-08-16 (`claude/crm_optimizacao_tasks/`) — é uma regressão de integridade de
dados causada indiretamente pela adição de novos `primary_actor_type`, nunca revisada até
agora.

## O que corrigir

Adicionar `primary_actor_type: primary_actor_type` (ou equivalente) ao `where` da query de
dedup, escopando corretamente por tipo além de por ID.

## Testes

Testar manualmente (ou via `rails console`): criar uma `Notification` com
`primary_actor_type: 'Conversation', primary_actor_id: N` e outra com
`primary_actor_type: 'Task', primary_actor_id: N` (mesmo N) para o mesmo usuário, rodar o job
de dedup, confirmar que **nenhuma** das duas é removida por engano.

## Critério de pronto

- Dedup de notificação escopa corretamente por `primary_actor_type` além de
  `primary_actor_id`.
- Notificações de tipos diferentes com IDs numericamente coincidentes não são mais tratadas
  como duplicatas entre si.
- `bundle exec rubocop -a` limpo no arquivo tocado.

## Resultado (2026-09-30)

`primary_actor_type` acrescentado ao `where` do job, com o `where` quebrado em múltiplas linhas
(numa linha só ficaria a ~139 caracteres e o `.order` encadeado estouraria os 150).

**Contexto confirmado no código, que reforça a severidade:** o índice
`uniq_primary_actor_per_account_notifications` **não é unique** — é `t.index [...]` sem
`unique: true` (`db/schema.rb:1071`). O nome vem do upstream e engana. Não existe constraint de
banco nenhuma: a deduplicação é inteiramente responsabilidade deste job, que é enfileirado em
**toda** entrega de notificação (`notification.rb:186`, dentro de `process_notification_delivery`).

**Fora de escopo, registrado:** o dedup também não escopa por `notification_type`, então um
`conversation_mention` e um `assigned_conversation_new_message` da mesma conversa são tratados
como duplicatas entre si e o mais antigo é destruído. É comportamento do upstream e
plausivelmente intencional ("manter só a notificação mais recente sobre aquela conversa").
Mudar isso alteraria a semântica da deduplicação, que não é o que esta task pede.

### Verificação empírica

Spec temporário de diagnóstico (`tmp_dedup_debug_spec.rb`, apagado depois), replicando o cenário
do spec oficial e inspecionando a relação do job:

```
match count = 2
ids na ordem = [446, 445]
offset(1) ids = [445]
depois do job, ainda existem: [410, 446]
```

O `where` com `primary_actor_type` encontrou as duas notificações pretendidas, `offset(1)`
selecionou a mais antiga e ela **foi destruída** — o job funciona.

### ⚠️ Spec pré-existente quebrado (não causado por esta task)

`spec/jobs/notification/remove_duplicate_notification_job_spec.rb:15` ("removes duplicate
notifications") falha com `expected: 1, got: 2`. **Confirmado pré-existente**: restaurei o
arquivo do job com `git show HEAD:<arquivo>` e a falha é idêntica, com a mesma mensagem.

Causa diagnosticada: a asserção usa `Notification.count` **global** e a tabela tinha um registro
a mais (id 410), de outro usuário.

> **⚠️ Correção (2026-10-06):** o diagnóstico acima parou no lugar errado. Eu concluí aqui que a
> notificação extra era "efeito colateral dentro do exemplo", gerada pelo
> `let(:conversation) { create(:conversation) }`, e descartei resíduo porque `psql -d
> chatwoot_test` retornava 0 linhas. **O banco consultado não era o que a suíte usava.** A causa
> real é que `rspec` rodava contra o `chatwoot_dev` (o container define `RAILS_ENV=development`
> e o `rails_helper` usava `||=`), e a id 410 é uma linha real do banco de desenvolvimento —
> uma notificação `task_due` de `Task#39`, de 46 dias antes. Resolvido na
> [task 22](22-fix-specs-notificacao-contagem-global.md); os specs estavam corretos o tempo
> todo e não precisaram de alteração nenhuma.

Registrado como [task 22](22-fix-specs-notificacao-contagem-global.md), junto com
`remove_old_notification_job_spec.rb:32`, que falha pelo mesmo motivo (a notificação colateral
nasce com `created_at` ~42 dias no passado e é legitimamente apagada pelo
`remove_old_notifications`, mudando a contagem global).

**Rubocop:** limpo, após normalizar o arquivo de CRLF para LF — **4ª ocorrência** do problema
nesta base (ver `claude/pipeline_performance_tasks/` tasks 22 e 29, e as tasks 01-03 desta pasta).
