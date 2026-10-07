# Specs que já falhavam antes do épico CRM

## Objetivo

Registrar os specs que falham no `develop` **independentemente** das nossas mudanças, para que
não sejam confundidos com regressão na próxima vez que alguém rodar a suíte — e para que possam
ser revisados quando houver espaço.

Nenhum item aqui é causado pelo épico CRM (`claude/crm_features_fixes_tasks/`, commit
`e45c5c2c3`). Levantado em 2026-10-07.

## Como rodar a suíte nesta base

O container define `RAILS_ENV=development`, e desde a task 22 do épico CRM o
`spec/rails_helper.rb` **força** `RAILS_ENV=test`. Se o banco de teste estiver atrás das
migrations:

```bash
docker exec -e RAILS_ENV=test chatwoot-noble-rails-1 bundle exec rails db:migrate
docker exec chatwoot-noble-rails-1 bundle exec rspec <arquivo>
```

> ⚠️ **Qualquer medição de spec anterior a 2026-10-06 nesta base é suspeita.** Até a task 22, o
> `rails_helper` usava `ENV['RAILS_ENV'] ||= 'test'`, que não sobrescreve — a suíte inteira
> rodava contra o `chatwoot_dev`. Isso produzia falhas que variavam conforme o estado do banco de
> desenvolvimento de cada máquina. Concretamente: `accounts_controller_spec` dava **8** falhas no
> dev e **7** no test.

## Inventário — 18 exemplos, 5 arquivos

### Grupo A — dependem de variável de ambiente (9 exemplos) · 🟡 Média

Todos usam o helper `with_modified_env` (`spec/spec_helper.rb:16`), que é um wrapper de
`ClimateControl.modify`.

**O helper em si funciona** — testado isoladamente no container:

```
gem carregada: 1.2.0
dentro do bloco: "valor"
depois do bloco: nil
```

Então a causa não é a gem nem o helper. Hipótese seguinte, a confirmar: algo lê o valor **antes**
do bloco e cacheia (`InstallationConfig`/`GlobalConfig` são semeados no boot e memoizados), ou as
expectativas dos specs divergiram do código. Em todo caso, 9 exemplos com a mesma assinatura
provavelmente têm uma causa única.

```
spec/controllers/api/v1/accounts_controller_spec.rb:17    # calls account builder
spec/controllers/api/v1/accounts_controller_spec.rb:34    # calls ChatwootCaptcha
spec/controllers/api/v1/accounts_controller_spec.rb:54    # renders error response on invalid params
spec/controllers/api/v1/accounts_controller_spec.rb:74    # creates a second account
spec/controllers/api/v1/accounts_controller_spec.rb:149   # CW_API_ONLY_SERVER
spec/controllers/platform/api/v1/accounts_controller_spec.rb:48    # feature flags
spec/controllers/platform/api/v1/accounts_controller_spec.rb:178   # permissible object
spec/models/integrations/app_spec.rb:32   # SLACK_CLIENT_ID na action URL
spec/models/integrations/app_spec.rb:47   # SLACK_CLIENT_SECRET em #active?
```

Os de `accounts_controller` giram em torno de `ENABLE_ACCOUNT_SIGNUP` e `CW_API_ONLY_SERVER`;
os de `integrations/app` em torno das credenciais do Slack.

### Grupo B — cálculo de tempo de resposta (4 exemplos) · 🟡 Média

```
spec/models/conversation_spec.rb:1025   # tracks waiting_since / first response time events
spec/models/conversation_spec.rb:1053
spec/models/conversation_spec.rb:1105   # reply time a partir da mensagem mais recente após o bot
spec/models/conversation_spec.rb:1128
```

Usam tempos relativos (`4.hours.ago`, `10.hours.ago`) com `be_within`. Candidatos naturais a
fragilidade por fuso horário ou por ordem de criação das mensagens.

### Grupo C — mailers (4 exemplos) · 🟢 Baixa

```
spec/mailers/confirmation_instructions_spec.rb:41   # default confirmation state
spec/mailers/confirmation_instructions_spec.rb:56   # refers to the inviter and their account
spec/mailers/conversation_reply_mailer_spec.rb:642  # custom domain e email desabilitado
spec/mailers/conversation_reply_mailer_spec.rb:661  # reply-to do inbox
```

### Grupo D — configuração de instalação (1 exemplo) · 🟢 Baixa

```
spec/models/concerns/account_email_rate_limitable_spec.rb:12   # global config quando não há override
```

Usa `InstallationConfig.where(name: 'ACCOUNT_EMAILS_LIMIT').first_or_create(value: 200)`.
Depende do estado da tabela `installation_configs`, que é semeada no boot.

## Prova de que são pré-existentes

**Grupos A (parte de `accounts_controller`)** — medido duas vezes, por caminhos independentes:

1. Na task 21, restaurei o `swagger/swagger.json` do `HEAD` via `git show` e rodei os mesmos dois
   arquivos: resultado idêntico, descartando o rebuild do Swagger como causa.
2. Na task 22, repetido com `RAILS_ENV=test`: 8 falhas viraram 7 — uma era artefato do banco de
   dev, as outras 7 são reais e pré-existentes.

**Grupos A (parte de `integrations`), B, C e D** — revertí as quatro configurações da task 24 com
`git checkout e45c5c2c3^ --` e rodei exatamente os mesmos 11 exemplos:

```
grep da linha da task 24 em application.rb -> 0   (confirma que a reversão estava ativa)
11 examples, 11 failures
```

Com a task 24 aplicada, os mesmos 11 falham. **11 de 11 nos dois cenários** — a mudança de i18n
não tem relação com eles. (O grupo C também foi testado isoladamente antes, com o mesmo
resultado: 4 falhas com e sem a mudança.)

## Nota sobre a contagem

A execução de `spec/mailers/ spec/models/` reporta **15 failures** para **11** linhas de rerun
(`rspec ./spec/...`). A diferença são exemplos com mais de uma expectativa falhando no mesmo
bloco. A lista de 11 é a autoritativa, porque é a que o RSpec manda rodar de novo.

## O que está verde

Vale registrar o contraponto, porque é a área que o épico CRM tocou:
`spec/jobs/notification/`, `spec/models/concerns/switch_locale_spec.rb`,
`spec/models/notification_spec.rb`, `spec/drops/`, `spec/policies/pipeline_item_policy_spec.rb`,
`spec/models/pipeline_item_spec.rb`, `spec/swagger/openapi_spec.rb`,
`spec/controllers/api/v1/accounts/pipelines_controller_spec.rb` e
`spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` — todos passando.

## Próximo passo sugerido

Capturar a mensagem de erro de cada grupo e, a partir dela, decidir se o defeito está no spec
(frágil) ou no código.

Comece pelo **grupo A**: são 9 dos 18 exemplos, com a mesma assinatura, e o helper já foi
descartado como causa — o que resta é um ponto de cache ou expectativas desatualizadas, e
qualquer dos dois provavelmente resolve os 9 de uma vez.

```bash
docker exec chatwoot-noble-rails-1 bundle exec rspec \
  spec/models/integrations/app_spec.rb:32 \
  spec/controllers/api/v1/accounts_controller_spec.rb:17
```

Dois exemplos de arquivos diferentes, o menor par que representa o grupo — bem mais rápido que
rodar os 18.
