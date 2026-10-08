# Specs que já falhavam antes do épico CRM

## Objetivo

Registrar os specs que falham no `develop` **independentemente** das nossas mudanças, para que
não sejam confundidos com regressão na próxima vez que alguém rodar a suíte — e para que possam
ser revisados quando houver espaço.

Nenhum item aqui é causado pelo épico CRM (`claude/crm_features_fixes_tasks/`, commit
`e45c5c2c3`). Levantado em 2026-10-07.

**18 exemplos, 5 arquivos.** Treze deles têm causa identificada e nenhuma é bug de produção: são
specs do upstream que não acompanharam mudanças deliberadas deste fork, ou specs sensíveis à
velocidade da máquina.

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
> rodava contra o `chatwoot_dev`. Concretamente: `accounts_controller_spec` dava **8** falhas no
> dev e **7** no test.

---

## Grupo A — o spec seta ENV, o código lê de outro lugar (7 exemplos) · 🟡 Média

```
spec/controllers/api/v1/accounts_controller_spec.rb:17   expect(AccountBuilder).to have_received(:new)
spec/controllers/api/v1/accounts_controller_spec.rb:34   expect(ChatwootCaptcha).to have_received(:new).with('123')
spec/controllers/api/v1/accounts_controller_spec.rb:54   esperava 403, veio 404
spec/controllers/api/v1/accounts_controller_spec.rb:74   esperava 2xx, veio 404
spec/controllers/api/v1/accounts_controller_spec.rb:149  esperava 2xx, veio 404
spec/models/integrations/app_spec.rb:32                  client_id saiu vazio na URL do Slack
spec/models/integrations/app_spec.rb:47                  app.active?(account) deu false
```

**Diagnóstico.** Os specs envolvem a chamada em `with_modified_env ENABLE_ACCOUNT_SIGNUP: 'true'`
(ou `SLACK_CLIENT_ID`), que altera a **variável de ambiente**. Mas o código não lê do ambiente:

```ruby
# app/controllers/api/v1/accounts_controller.rb:125-127
def check_signup_enabled
  raise ActionController::RoutingError, 'Not Found' unless GlobalConfigService.account_signup_enabled?
end
```

`GlobalConfigService` resolve a flag pelo `InstallationConfig` (tabela no banco), não pelo ENV. O
próprio arquivo tem um comentário explicando por quê, logo abaixo:

```ruby
# Read ENABLE_ACCOUNT_SIGNUP raw from InstallationConfig because GlobalConfig.get
# typecasts it to boolean, coercing 'api_only' to true.
```

Com o cadastro desabilitado, o `check_signup_enabled` levanta `RoutingError` → **404**. Daí a
cascata: o `AccountBuilder` e o `ChatwootCaptcha` nunca são chamados (as duas primeiras falhas),
porque a request morre antes.

O helper em si está íntegro — testei isoladamente:

```
ClimateControl 1.2.0 | dentro do bloco: "valor" | depois do bloco: nil
```

Os dois de `Integrations::App` são a mesma família: a URL saiu com `client_id=` **vazio**, ou
seja, o valor foi lido num momento em que o bloco do `with_modified_env` já não valia (config
carregada no boot).

**Correção provável:** os specs devem semear `InstallationConfig`, não o ENV. É mudança só de
spec; o código está certo e tem justificativa escrita.

---

## Grupo B — specs sensíveis à velocidade da máquina (4 exemplos) · 🟡 Média

```
spec/models/conversation_spec.rb:1025   expected 3698.0 to be within 1 of 1 hour
spec/models/conversation_spec.rb:1053   expected 3670.0 to be within 1 of 1 hour
spec/models/conversation_spec.rb:1105   expected 3669.0 to be within 60 of 3600
spec/models/conversation_spec.rb:1128   expected 3685.0 to be within 60 of 3600
```

**Diagnóstico.** Os quatro erram **para mais**, por 69 a 98 segundos. Não é coincidência: é o
tempo de parede que o exemplo leva para rodar.

O valor do evento é a diferença entre dois `created_at` (`reporting_event_listener.rb:30`):

```ruby
first_response_time = message.created_at.to_i - last_non_human_activity(conversation).to_i
```

E o spec monta os dois instantes em **momentos diferentes da execução**:

```ruby
let(:conversation_start_time) { 5.hours.ago }   # linha 984, avaliado no primeiro uso (linha 990)
...
agent_reply1_time = 4.hours.ago                 # avaliado bem depois, dentro do exemplo
```

Se passam Δ segundos entre as duas avaliações, a diferença vira `1 hora + Δ` em vez de 1 hora
exata. Com `be_within(1.second)`, qualquer máquina que leve mais de um segundo entre as linhas
reprova. Este container é lento o bastante para somar ~1,5 minuto.

**Isso não é bug de produção** — o cálculo está correto. São specs que assumem execução
instantânea. Correção: congelar o tempo com `travel_to` em vez de recalcular `.ago` em pontos
diferentes.

---

## Grupo C — white-label: os specs ainda esperam a marca "Chatwoot" (2 exemplos) · 🟢 Baixa

```
spec/mailers/confirmation_instructions_spec.rb:41
  expect(mail_body).to include('Welcome to Chatwoot. We just need to verify your email address...')
spec/mailers/confirmation_instructions_spec.rb:56
  expect(mail_body).to include("#{inviter.name} invited you to join the #{account.name} workspace on Chatwoot.")
```

**Diagnóstico.** O template já foi white-labeled e interpola a marca:

```erb
<%# app/views/devise/mailer/confirmation_instructions.html.erb:12 e :39 %>
"Welcome to #{brand_name}. We just need to verify your email address before you can start using your account."
"#{inviter.name} invited you to join the #{account_name} workspace on #{brand_name}."
```

Os specs ficaram com a string literal `Chatwoot`. São **specs obsoletos para este fork**, não
defeito: o e-mail está certo, com a marca da Noble. Correção: usar `brand_name` na expectativa.

---

## Grupo D — a confirmar (5 exemplos) · 🟢 Baixa

Causa não investigada; só a asserção que falhou está registrada.

```
spec/controllers/platform/api/v1/accounts_controller_spec.rb:48
spec/controllers/platform/api/v1/accounts_controller_spec.rb:178
  expect(...enabled_features.keys).to match_array(%w[inbox_management ip_lookup help_center])
  → provável drift entre o spec e os defaults de config/features.yml

spec/models/concerns/account_email_rate_limitable_spec.rb:12
  expect(account.email_rate_limit).to eq(200)
  → depende do valor semeado de ACCOUNT_EMAILS_LIMIT em installation_configs

spec/mailers/conversation_reply_mailer_spec.rb:642   expect(mail.reply_to).to eq([...assignee&.email])
spec/mailers/conversation_reply_mailer_spec.rb:661   expect(mail.from).to eq([inbox.email_address])
```

---

## Prova de que nenhum deles é nosso

**Parte do grupo A (`accounts_controller`)** — medido por dois caminhos independentes:

1. Na task 21, restaurei o `swagger/swagger.json` do `HEAD` via `git show` e rodei os mesmos dois
   arquivos: resultado idêntico, descartando o rebuild do Swagger.
2. Na task 22, repetido com `RAILS_ENV=test`: 8 falhas viraram 7 — uma era artefato do banco de
   dev, as outras 7 são reais e pré-existentes.

**Os 11 exemplos de `models/` e `mailers/`** — revertí as quatro configurações da task 24 com
`git checkout e45c5c2c3^ --` e rodei exatamente os mesmos exemplos:

```
grep da linha da task 24 em application.rb -> 0   (confirma a reversão ativa)
11 examples, 11 failures
```

Com a task 24 aplicada, os mesmos 11 falham. **11 de 11 nos dois cenários.** O grupo C também foi
testado isoladamente antes, com o mesmo resultado nos dois sentidos.

## Nota sobre a contagem

A execução de `spec/mailers/ spec/models/` reporta **15 failures** para **11** linhas de rerun.
A diferença são exemplos com mais de uma expectativa falhando no mesmo bloco. A lista de 11 é a
autoritativa, porque é a que o RSpec manda rodar de novo. Rodando os 18 isoladamente:
`18 examples, 18 failures`.

## O que está verde

O contraponto, que é a área tocada pelo épico CRM: `spec/jobs/notification/`,
`spec/models/concerns/switch_locale_spec.rb`, `spec/models/notification_spec.rb`, `spec/drops/`,
`spec/policies/pipeline_item_policy_spec.rb`, `spec/models/pipeline_item_spec.rb`,
`spec/swagger/openapi_spec.rb` e os dois specs de request de pipeline — todos passando.

## Ordem sugerida para atacar

1. **Grupo C** (2 exemplos) — a correção é trocar uma string literal por `brand_name`. Mais
   rápido e sem risco.
2. **Grupo A** (7 exemplos) — uma causa só: trocar `with_modified_env` por semear
   `InstallationConfig`. Começar pelo par mais barato, um de cada arquivo:
   ```bash
   docker exec chatwoot-noble-rails-1 bundle exec rspec \
     spec/models/integrations/app_spec.rb:32 \
     spec/controllers/api/v1/accounts_controller_spec.rb:17
   ```
3. **Grupo B** (4 exemplos) — envolver os exemplos em `travel_to`.
4. **Grupo D** (5 exemplos) — investigar a causa primeiro.
