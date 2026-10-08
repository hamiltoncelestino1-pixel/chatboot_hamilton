# Task 22 — Fix: a suíte de specs rodava contra o banco de desenvolvimento

Severidade: 🟠 Alta (era 🟡 Média enquanto o diagnóstico estava errado). Achado durante a
implementação das tasks 10 e 13 (2026-09-30); causa raiz real encontrada em 2026-10-06.

> **⚠️ Esta task foi reescrita.** A versão original afirmava que o problema eram duas asserções
> frágeis de contagem global, causadas por uma notificação colateral criada dentro do próprio
> exemplo. **Esse diagnóstico estava errado** — e era meu, de uma sessão anterior. O que a
> versão original dizia sobre "não ser dado residual" se apoiava numa consulta ao
> `chatwoot_test`, que era o banco errado para checar. O histórico do engano está registrado na
> seção final, porque ele explica por que o sintoma enganou.

## Sintoma

Dois specs em `spec/jobs/notification/` falhavam:

```
remove_duplicate_notification_job_spec.rb:15   expected: 1, got: 2
remove_old_notification_job_spec.rb:32         expected `Notification.count` not to have
                                               changed, but did change from 51 to 50
```

## Causa raiz

A suíte rodava contra o **banco de desenvolvimento**:

```
banco em uso = chatwoot_dev
```

- `docker-compose.yaml:42` define `RAILS_ENV=development` no container.
- `spec/rails_helper.rb:2` fazia `ENV['RAILS_ENV'] ||= 'test'` — e `||=` **não sobrescreve** um
  valor já presente no ambiente.

Logo, todo `docker exec ... bundle exec rspec` carregava `config/environment` em modo
development e conectava no `chatwoot_dev`.

A "notificação colateral" que o diagnóstico antigo atribuía ao `create(:conversation)` é, na
verdade, **uma linha real do banco de dev**:

```
id=410 user=1 task_due Task#39 criada=2026-08-21   (46 dias atras)
```

Nenhum dos dois specs cria uma `Task`, e `user=1` não é um usuário criado por eles (os do spec
nascem com id na casa dos milhares). É um registro de uso real da aplicação em dev.

Como `use_transactional_fixtures` reverte o que o exemplo escreve mas **não esconde o que já
estava lá**, qualquer asserção sobre `Notification.count` global passava a contar essa linha.
Por isso só esses dois exemplos quebravam: são os únicos que contam a tabela inteira.

## Correção

`spec/rails_helper.rb` passou a **atribuir** em vez de usar `||=`:

```ruby
ENV['RAILS_ENV'] = 'test'
```

Seguro porque `spec_helper.rb` (requerido na linha anterior) não carrega o Rails — só
`webmock` —, então a atribuição acontece antes do `require config/environment`.

**Os dois specs não foram alterados.** Eles estão corretos; a invocação é que estava errada.
Escopar as asserções por usuário, como a versão original desta task propunha, teria mascarado o
problema real e deixado a suíte inteira rodando no banco de dev.

## Verificação

Banco de teste estava atrás das migrations (faltava a `recurrence_anchor_at` da task 13):

```bash
docker exec -e RAILS_ENV=test chatwoot-noble-rails-1 bundle exec rails db:migrate
```

Depois, **sem** passar `-e RAILS_ENV=test` (ou seja, pelo caminho que qualquer pessoa usa):

```
spec/jobs/notification/        -> 13 examples, 0 failures
```

E a confirmação direta de qual banco a suíte usa agora:

```
spec usa: chatwoot_test | Rails.env=test
Notification.count no inicio = 0
```

Não-regressão nos specs do domínio Pipeline (criados na task 21, que tinham sido validados no
ambiente errado):

```
openapi + pipelines + pipeline_items + policy + model -> 47 examples, 0 failures
```

**Rubocop:** as 2 offenses em `spec/rails_helper.rb` (`Rails/Output` e `Rails/Exit`, linhas
42-43) são pré-existentes — confirmado com `git stash` da minha mudança e resultado idêntico.

## Impacto além dos dois specs

Rodar a suíte contra o banco de dev não era só ruído de contagem:

1. Toda execução consumia sequences de id do banco de desenvolvimento.
2. Qualquer spec que escrevesse fora de uma transação poderia alterar dados reais de dev —
   `use_transactional_fixtures` cobre a maior parte, mas não é garantia (jobs com
   `perform_now` que fazem `delete_all`, código que abre conexão própria, etc.).
3. Resultados de suíte ficavam dependentes do estado do dev de cada máquina, o que torna
   "falha pré-existente" uma categoria não confiável.

Exemplo concreto do item 3, medido nesta task: `accounts_controller_spec.rb` +
`platform/accounts_controller_spec.rb` davam **8 falhas** em dev e **7** em test — uma das
"falhas pré-existentes" reportadas na task 21 era artefato do banco de dev.

## Como o diagnóstico anterior errou

Vale registrar, porque o sintoma é enganoso:

- A medição original mostrou uma notificação a mais, de outro usuário, e **assumiu** que vinha
  do `create(:conversation)` do próprio spec — plausível, já que criar conversa realmente
  dispara listeners que geram notificação.
- Para descartar resíduo, consultou `psql -d chatwoot_test` e viu 0 linhas. O banco estava
  mesmo vazio — **mas não era o banco que a suíte usava**. A consulta certa teria sido no
  `chatwoot_dev`, ou simplesmente imprimir
  `ActiveRecord::Base.connection.current_database` dentro de um exemplo.
- A lição prática: antes de concluir qualquer coisa sobre estado de banco em spec, imprimir o
  banco em uso. Foi isso que resolveu em um minuto o que ficou duas sessões sem explicação.

## Critério de pronto

- [x] `bundle exec rspec` no container roda contra `chatwoot_test`, sem precisar de `-e`.
- [x] Os dois specs passam, sem alteração neles.
- [x] Nenhuma regressão nos specs do domínio Pipeline.
- [x] `CLAUDE.md` documenta o comportamento e o `db:migrate` do banco de teste.
