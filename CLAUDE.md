# CLAUDE.md — Guia do Projeto (Chatwoot Noble)

Guia mestre lido em toda sessão do Claude Code. Baseado em leitura direta do código deste
repositório (não em suposições sobre "como o Chatwoot costuma ser") — cada afirmação abaixo
cita o arquivo que a comprova. Onde não deu pra confirmar com certeza, está marcado
**"a confirmar"**.

Este projeto originou de um open-source (Chatwoot v4.13.0), mas mudou tanto — Kanban/Pipeline,
modo de atribuição por demanda, white-label completo, remoção de reset de branding — que hoje é
produto próprio da Noble Company. Este arquivo não trata "manter compatibilidade/paridade com
upstream" como objetivo.

Documentação complementar (não duplicada aqui, leia se precisar de mais profundidade):
- [`AGENTS.md`](AGENTS.md) — regras operacionais: comandos de build/test/lint, estilo de
  código, convenção de commits/PR. **Fonte da verdade para essas regras** — se este CLAUDE.md
  e o AGENTS.md divergirem em algo operacional, o AGENTS.md vence.
- [`claude/README.md`](claude/README.md) e os 10 guias numerados (`claude/01-*.md` …
  `claude/10-*.md`) — aprofundam estrutura de projeto, backend, frontend, white-label, receita
  de feature nova, integrações, `enterprise/`, ambiente Docker local, deploy e fluxo de git.
- `claude/pipeline_tasks/`, `claude/assignment_tasks/`, `claude/premium_unlock_tasks/`,
  `claude/white-label/` — históricos task-a-task de épicos já implementados (ou em
  implementação) que servem de exemplo real de como algo parecido foi construído.

---

## 1. Stack e versões

**Backend**
- Ruby `3.4.4` (`.ruby-version`, `Gemfile:3`) · Rails `~> 7.1`, lockado em `7.1.5.2`
  (`Gemfile:7`, `Gemfile.lock:710-712`)
- Postgres via gem `pg 1.5.3` (`Gemfile:66`); imagem de dev `pgvector/pgvector:pg16`
  (Postgres 16 + extensão pgvector, `docker-compose.yaml:87-97`)
- Redis `5.0.6` + `redis-namespace` (`Gemfile:67-68`); container dev exige senha via
  `REDIS_PASSWORD` (`docker-compose.yaml:99-106`)
- Sidekiq `7.3.1` (`Gemfile:136`) + `sidekiq-cron`, `sidekiq_alive`, `sentry-sidekiq`; roda
  como serviço próprio no compose: `bundle exec sidekiq -C config/sidekiq.yml`
  (`docker-compose.yaml:53-67`)
- Autorização: **Pundit `2.3.0`** (`Gemfile:93`), incluído globalmente em
  `app/controllers/application_controller.rb:4`
- Pub/sub de eventos: **Wisper `2.0.0`** (`Gemfile:102`) — ver seção 2
- Auth: `devise`, `devise_token_auth`, `devise-two-factor` (`Gemfile:85-90`)
- Sem `aasm`/state-machine gem — enums e métodos manuais fazem esse papel (ex.
  `Conversation#toggle_status`, `app/models/conversation.rb:149-154`, com um
  `# FIXME: implement state machine with aasm` deixado no código)
- Testes: `rspec-rails`, `factory_bot`, `shoulda-matchers`, `test-prof`, **Skooma** (valida
  specs de request contra `swagger/swagger.json`) — todos wireados em `spec/rails_helper.rb`

**Frontend**
- **Vue 3.5** (`package.json`: `"vue": "^3.5.12"`) — não é Vue 2
- Estado: **Vuex 4** (`store/modules/`, dominante/legado) **+ Pinia** (`stores/`, novo, uso
  mínimo hoje: só `stores/calls.js` e `stores/companies.js`)
- Vue Router 4 (`~4.4.5`)
- Build: **Vite 5** via `vite-plugin-ruby` (`vite.config.ts`) — **não é Webpacker**
- Testes: **Vitest 3** (`vite.config.ts` bloco `test:`) — **não é Jest**
- Lint: ESLint 8 (`.eslintrc.js`, legado não-flat-config, `airbnb-base` + `vue3-recommended`)
- Formatter: Prettier 3 (`.prettierrc`)
- **Sem TypeScript em código de aplicação** — só arquivos de config usam `.ts`
  (`vite.config.ts`, `histoire.config.ts`); nenhum `tsconfig.json` no repo
- i18n: `vue-i18n 9`, 58 pastas de locale em
  `app/javascript/dashboard/i18n/locale/`
- Gerenciador de pacotes: pnpm `10.x`, Node `24.x`
- App version atual: `4.13.0` (`package.json`, confirma a base de origem citada em
  `claude/README.md:4`)

---

## 2. Arquitetura

### Backend — `app/`

Pastas em `app/` e o papel de cada uma (confirmado por `ls app/` + leitura de exemplos):

| Pasta | Papel | Exemplo lido |
|---|---|---|
| `models/` | Entidades AR, sempre `belongs_to :account` quando tenant-scoped | `app/models/contact.rb`, `pipeline.rb` |
| `controllers/` | Namespacing `Api::V1::Accounts::*` para recursos de conta | `api/v1/accounts/pipeline_items_controller.rb` |
| `services/` | Lógica de negócio fora do request/model, `Namespace::VerbService#perform` | `automation_rules/action_service.rb` |
| `jobs/` | Sidekiq, `queue_as :symbol` por job | `action_cable_broadcast_job.rb` (`:critical`) |
| `builders/` | PORO com `pattr_initialize` (gem `attr_extras`) + `#perform` | `conversation_builder.rb` |
| `listeners/` | Assinantes Wisper, `Singleton`, um método por nome de evento | `automation_rule_listener.rb` |
| `dispatchers/` | Publica eventos via Wisper (sync/async) | `sync_dispatcher.rb`, `async_dispatcher.rb` |
| `policies/` | Pundit, `ApplicationPolicy` base + `Scope` por model | `pipeline_policy.rb` |
| `channels/` | ActionCable | `room_channel.rb` |
| `views/api/**/*.json.jbuilder` | Serialização JSON das respostas da API (**não** há `ActiveModel::Serializer`/`app/serializers/` neste projeto) | `views/api/v1/accounts/pipeline_items/show.json.jbuilder` |

Outras pastas presentes mas não detalhadas aqui: `mailboxes/`, `mailers/`, `presenters/`,
`drops/`, `finders/`, `actions/`, `dashboards/`, `helpers/`. `app/services/` mistura services
soltos (`csat_survey_service.rb`) e namespaced (`automation_rules/`, `contacts/`, `macros/`,
`crm/`) — não há uma regra rígida de "sempre namespaced", ambos coexistem.

**Multi-tenancy** é por convenção, não por gem:
- Toda tabela tenant-scoped tem coluna `account_id` + FK, e uniqueness scoped a ela, ex.
  `validates :email, uniqueness: { scope: [:account_id] }` (`app/models/contact.rb:51-56`)
- `Current` (`lib/current.rb`, `thread_mattr_accessor`) carrega `account`/`user`/
  `account_user`/`executed_by`/`contact` durante o request — usado o tempo todo pra saber
  "quem tá fazendo isso" (ex. `Current.executed_by = rule` em
  `app/services/automation_rules/action_service.rb:8`)
- Controllers sempre operam através de `Current.account.<associação>`, nunca de queries
  globais sem escopo

**Pub/sub de eventos (Wisper)** — fluxo completo, ponta a ponta:
1. Model dispara `Rails.configuration.dispatcher.dispatch(EVENT, Time.zone.now, data)` num
   callback `after_*_commit` (ex. `Conversation`, `Contact`, `PipelineItem`)
2. `Dispatcher` (Singleton, `config/initializers/event_handlers.rb:3-4`) repassa pra
   `SyncDispatcher` **e** `AsyncDispatcher`
3. `SyncDispatcher` (`app/dispatchers/sync_dispatcher.rb:7-9`) publica **síncrono**, só pra
   `ActionCableListener` e `AgentBotListener` — ou seja, só broadcast em tempo real e webhook
   de agent-bot rodam inline no request
4. `AsyncDispatcher` (`app/dispatchers/async_dispatcher.rb:12-22`) enfileira
   `EventDispatcherJob` (Sidekiq); é aí que roda `AutomationRuleListener`,
   `CampaignListener`, `WebhookListener` etc. — **automações rodam assíncronas**
5. Cada listener é `Singleton` (`app/listeners/base_listener.rb:2`), assinado uma vez no boot,
   com um método por nome de evento resolvido pelo Wisper

**ActionCable (tempo real)** — cadeia model → frontend:
1. Model dispatcha evento (ponto acima)
2. `ActionCableListener` (`app/listeners/action_cable_listener.rb`) calcula os
   `pubsub_token`s de destino (agentes/admins do inbox, tokens de contato, ou
   `account_#{id}` pra eventos account-wide como pipeline items) e enfileira
   `ActionCableBroadcastJob`
3. `ActionCableBroadcastJob` (`app/jobs/action_cable_broadcast_job.rb`, `queue_as :critical`)
   chama `ActionCable.server.broadcast(token, {event, data})` de fato
4. `RoomChannel` (`app/channels/room_channel.rb`) faz `stream_from pubsub_token` e, pra
   usuários logados, também `stream_from "account_#{id}"`
5. Frontend: `app/javascript/dashboard/helper/actionCable.js` — `ActionCableConnector` com
   mapa `events` (`'pipeline_item.created' → onPipelineItemChanged`, etc.), despachando pra
   uma action Vuex (ex. `kanban/applyRealtimePipelineItem`)
6. Nomes de evento centralizados em `lib/events/types.rb` — strings do backend e chaves do
   mapa `events` no frontend precisam ser mantidas em sincronia manualmente (sem codegen)

**Pundit (autorização)**:
- `ApplicationPolicy` base (`app/policies/application_policy.rb`) — `initialize(user_context,
  record)`, `Scope#resolve` default retorna tudo, `show?` default checa `scope.exists?`
- Controllers chamam `policy_scope(Current.account.<assoc>)` antes de `.find`, e
  `before_action :check_authorization` que chama `authorize(model)`
  (`app/controllers/api/v1/accounts/pipeline_items_controller.rb`)
- Cada policy decide seu próprio nível de restrição — não é uniforme: `PipelinePolicy`
  restringe `Scope#resolve` a `user.assigned_pipelines`, mas `PipelineItemPolicy` não
  restringe no nível do item (a restrição real acontece um nível acima, na policy do
  pipeline pai — comentário explicativo em `macros_controller.rb:62-64`)

**`enterprise/`**: pasta que estende/sobrescreve `app/` via `Model.prepend_mod_with('Model')`
/ `include_mod_with('Concerns::Model')` (`app/models/account.rb:212-215`). É organização de
código nossa — todo o enterprise já está liberado neste projeto (ver seção 5), não é uma
camada "premium" a proteger nem um checklist de compatibilidade de licença. Ao mexer em lógica
core, vale conferir se existe módulo correspondente em `enterprise/` e manter os dois
sincronizados (`claude/07-enterprise.md` tem o guia completo).

### Frontend — `app/javascript/dashboard/`

| Pasta | Papel | Exemplo |
|---|---|---|
| `api/` | Um cliente por recurso, `class XyzAPI extends ApiClient`, exporta singleton `new XyzAPI()` | `api/macros.js`, `api/ApiClient.js` |
| `composables/` | Funções Vue 3 Composition API — puras ou ponte pra Vuex via `composables/store.js` (`useStore`/`useMapGetter`) | `composables/useEditableAutomation.js` |
| `store/modules/` | **Vuex 4**, namespaced, forma `{state, getters, actions, mutations}` | `store/modules/kanban/` |
| `stores/` | **Pinia**, novo, pouco uso ainda | `stores/calls.js` |
| `components/` | Componentes legados, ainda com Options API em partes | — |
| `components-next/` | Árvore nova, **preferida para UI nova** (`AGENTS.md`) | `components-next/NewConversation/` |
| `routes/dashboard/<feature>/` | `routes.js` + páginas + `components/` locais, um diretório por feature | `routes/dashboard/kanban/` |
| `helper/` | Utilitários agnósticos de framework | `helper/actionCable.js` |
| `i18n/locale/` | Traduções, ver seção 3 | — |

`api/ApiClient.js` é a base class de toda chamada HTTP: `get/show/create/update/delete`
montando URL a partir de `resource` + flags `accountScoped`/`enterprise`. Todo arquivo em
`api/` estende essa classe e exporta uma instância singleton.

Padrão de módulo Vuex (`store/modules/kanban/actions.js`): actions assíncronas recebendo
`{commit, state}`, chamando `api/*`, commitando flags de UI (`SET_KANBAN_UI_FLAG`) antes/depois
em `try/finally`, com rollback otimista em `catch` + `useAlert(...)` (composable importado
direto num arquivo Vuex).

---

## 3. Convenções de código

**Nomenclatura**
- Componentes Vue em PascalCase; nomes de um só termo são permitidos
  (`vue/multi-word-component-names: off`, `.eslintrc.js`)
- Eventos em camelCase
- `<script setup>` é o padrão **para código novo** (`AGENTS.md`) — mas isso é uma meta, não
  o estado atual de todo o código: `MacroForm.vue`
  (`routes/dashboard/settings/macros/MacroForm.vue`) ainda é Options API + Vuelidate. Não
  assuma que tudo no repo já é Composition API — cheque o arquivo antes de replicar um padrão

**Testes — backend (RSpec)**
- `spec/` espelha `app/` (`spec/models/`, `spec/services/`, `spec/policies/`, etc.)
- FactoryBot: `after(:build)`/`after(:create)` pra associações obrigatórias lazy, `trait` pra
  variações (`spec/factories/pipeline_items.rb:9-21`)
- `shoulda-matchers` para validações simples (`it { is_expected.to validate_presence_of(:x) }`)
- Specs de `:request` **podem** ser validados contra `swagger/swagger.json` via Skooma, mas a
  validação é **opt-in por exemplo**: o `config.include Skooma::RSpec[...]`
  (`spec/rails_helper.rb:79-81`) só disponibiliza o matcher. Sem escrever
  `expect(response).to conform_schema(200)` no exemplo, nada é verificado — e dos 181 arquivos
  `type: :request`, só ~10 o fazem hoje. **Ao criar ou mudar um endpoint, acrescente o matcher
  no exemplo de sucesso**, senão a documentação diverge em silêncio (foi assim que as tasks 11,
  12 e 21 de `claude/crm_features_fixes_tasks/` acumularam divergências). O matcher se chama
  `conform_schema`/`conform_response_schema` — **não** `conform_to_definition`, que é de outra
  gem. `spec/swagger/openapi_spec.rb` valida o documento em si com `be_valid_document`.
  Ver `claude/06-integracoes.md` e a regra de memória sobre `swagger:build`
- `AGENTS.md` é explícito: **não escreva specs a menos que peçam** — regra real deste
  projeto, não suavizar

**Testes — frontend (Vitest)**
- Specs colocados junto do código: `*.spec.js` ao lado do arquivo, ou numa pasta local
  `specs/`/`spec/` (não existe `__tests__/` global)
- `shallowMount` é o padrão dominante em specs de componente; `mount` é exceção
- `vi.mock(...)` pra isolar composables/módulos irmãos; asserções em `toEqual`

**Lint Ruby (`.rubocop.yml`)**
- 4 cops customizados carregados de `./rubocop/*.rb` (`UseFromEmail`, `CustomCopLocation`,
  `Chatwoot/AttachmentDownload`, `Style/OneClassPerFile`)
- `Layout/LineLength Max: 150`, `Metrics/ClassLength Max: 175` (com excludes explícitos —
  este fork adicionou `app/listeners/action_cable_listener.rb` à lista de excludes)
- Sem `.rubocop_todo.yml` — desvios são geridos via excludes inline no próprio `.rubocop.yml`

**Lint JS/Vue (`.eslintrc.js`)**
- `airbnb-base/legacy` + `plugin:vue/vue3-recommended` + `prettier`
- `vue/no-bare-strings-in-template: error` — força tudo passar por i18n
- `vue/block-order: [script, template, style]`
- `vue/define-props-declaration: runtime` / `vue/define-emits-declaration: error` — props/emits
  são runtime (objeto/array), não TS
- `no-console: error`

**Commits**
- Conventional Commits: `type(scope): subject` (`AGENTS.md`)
- `Co-Authored-By: Claude ...` é prática aceita neste projeto — **não remover** esse trailer
  (regra corrigida no `AGENTS.md` nesta sessão; antes dizia o contrário e estava
  desatualizada em relação à prática real do histórico de commits)

**i18n**
- Regra geral (`AGENTS.md`): só editar `en.yml` (backend) e `en.json`-equivalente (frontend,
  na prática os arquivos em `i18n/locale/en/*.json`); outros idiomas são geridos pela
  comunidade/Crowdin (`crowdin.yml`)
- **Exceção real e ativa**: **todo domínio próprio deste fork mantém `en` + `pt_BR`
  sincronizados à mão.** A regra geral existe porque a comunidade/Crowdin traduz o conteúdo do
  upstream — e isso simplesmente não acontece com o que é só nosso: Kanban/Pipeline, Tasks,
  relatório de funil e as notificações desse domínio não existem no Chatwoot original, então
  nunca vão chegar traduzidos de lugar nenhum. Na prática, hoje isso cobre:
  `kanban.json`, `automation.json`, `macros.json`, `tasks.json`, `pipelineMgmt.json`, as
  chaves de pipeline/task em `settings.json`, e os blocos `notifications.*` / `errors.*` de
  pipeline/task/macro em `config/locales/pt_BR.yml`. **A regra é o critério ("é feature nossa?"),
  não essa lista** — a lista fica desatualizada, o critério não.
  Essa formulação substitui a versão antiga, que enumerava só três arquivos; foi justamente por
  enumerar que `tasks.json` (21 chaves, UI inteira em inglês) e `pipelineMgmt.json` (30 chaves)
  nasceram sem tradução. Ver `claude/crm_features_fixes_tasks/23-*.md`.
  Para qualquer domínio herdado do upstream, siga a regra geral (só `en`).
  **Cuidado ao criar um arquivo de locale novo**: ele precisa ser importado **e** espalhado em
  `i18n/locale/<locale>/index.js`, senão é ignorado em silêncio (foi o caso do `tasks.json`)
- Convenção de chave: namespace `SCREAMING_SNAKE_CASE` por feature, sub-namespace `API` pra
  mensagens de sucesso/erro — ex. `KANBAN.ITEM.API.CREATE_SUCCESS`
  (`i18n/locale/en/kanban.json`)
- **Pendência conhecida, não é bug do fork**: `onboarding.json` só existe em `en/` — em
  **nenhum** dos 58 locales (incluindo `pt_BR`) há tradução. Confirmado via
  `git log --all -- '.../pt_BR/onboarding.json'` (sem histórico — o arquivo nunca existiu
  nesse locale) e o arquivo `en/onboarding.json` veio de um commit **upstream** do Chatwoot
  (`224556fd1`, "feat: onboarding account details...", autor Shivam Mishra) que também nunca
  foi traduzido pra nenhum outro idioma. Não é algo revertido nem específico do pt_BR — é
  conteúdo novo do upstream ainda sem tradução em lugar nenhum. Documentado aqui só pra não
  ser confundido com um erro nosso; não precisa de ação.

---

## 4. Padrões específicos do domínio

**Modelos centrais e relação**
- `Account` = raiz de tenant, `has_many` quase tudo com `dependent: :destroy_async`
  (`app/models/account.rb:65,89-91`)
- `Inbox` liga a canais via `belongs_to :channel, polymorphic: true`
  (`app/models/inbox.rb:61`) — é assim que Whatsapp/Telegram/Email/WebWidget etc. plugam
- `Conversation`/`Contact` sempre `belongs_to :account`; ambos disparam eventos em
  `after_*_commit` (`Rails.configuration.dispatcher.dispatch`) — mesmo padrão usado por
  `PipelineItem`
- **Como adicionar um canal novo**: **a confirmar** — não foi investigado a fundo nesta
  sessão. Antes de implementar um canal, ler `claude/06-integracoes.md` e localizar um canal
  existente equivalente (`app/models/channel/*.rb`) como referência, em vez de assumir um
  passo a passo aqui.

**Padrão de API nova**
- Namespace `Api::V1::Accounts::*Controller` para recursos de conta;
  `Api::BaseController` cuida de autenticação dupla — token de agent-bot
  (`authenticate_access_token!`) vs sessão Devise (`authenticate_user!`)
  (`app/controllers/api/base_controller.rb:4-12`)
- `Api::V1::Accounts::BaseController` adiciona `before_action :current_account` (seta
  `Current.account`/`Current.account_user`)
- Serialização JSON via **Jbuilder** (`app/views/api/v1/accounts/**/*.json.jbuilder`) — não
  há `ActiveModel::Serializer` nem pasta `app/serializers/` neste projeto (confirmado, 0
  arquivos encontrados)
- Todo endpoint de request spec novo precisa bater com `swagger/swagger.json` (Skooma) —
  ver regra de memória sobre `docker exec chatwoot-noble-rails-1 bundle exec rails
  swagger:build` e registro em `paths/index.yml`

**Autorização por role**
- Pundit + `Current.account_user.administrator?` é o padrão pra ações restritas a admin, ex.
  `PipelinePolicy#create?/update?/destroy?` (`app/policies/pipeline_policy.rb:16-26`)

---

## 5. O que este projeto tem de próprio

Não tratado como "lista de diffs de um fork" — é o que o produto é hoje:

- **Kanban/Pipeline**: sistema completo (models `Pipeline`/`PipelineStage`/`PipelineItem`/
  `PipelineMember`, controllers, services em `app/services/automation_rules/` e
  `app/services/macros/`, ~18 migrations, frontend em `routes/dashboard/kanban/` +
  `store/modules/kanban/`, i18n próprio) — não existe no Chatwoot original. Detalhes em
  `claude/pipeline_tasks/00-visao-geral.md`.
- **Assignment mode / atribuição por demanda**: distribuição least-busy sem exigir agente
  online, com fallback anti-silêncio (commit `4248342f2`,
  `claude/assignment_tasks/00-visao-geral.md`).
- **Reset noturno de branding/plano removido de propósito** (commit `7780e789a`,
  `claude/premium_unlock_tasks/00-visao-geral.md`): o produto não volta mais pro branding
  padrão do Chatwoot todo dia — é comportamento definitivo, não uma trava contornada.
- **White-label completo pra Noble Company** (`claude/white-label/`) — nome, cores, logos e
  domínio são os nossos.
- Origem histórica: base v4.13.0 do Chatwoot open-source (citado uma única vez, sem tratar
  paridade com upstream como objetivo).

**Pendências de estado atual** (não fazem parte da identidade do projeto, só ainda não foram
atualizadas — marcar como "a confirmar/atualizar" se for mexer nessas áreas):
- `README.md`/`CONTRIBUTING.md` na raiz ainda têm texto genérico do Chatwoot original
- `docker-compose.production.yaml` ainda referencia `image: chatwoot/chatwoot:latest` em vez
  de uma imagem própria (gap já registrado em `claude/09-deploy-producao.md`)
- `.github/workflows/` foi removido (commit `cc0046185`) — CI atual não roda GitHub Actions;
  **a confirmar** qual pipeline de CI (se algum) está em uso hoje

---

## 6. Comandos úteis

Fonte primária: [`AGENTS.md`](AGENTS.md) — segue resumo, mas confira lá se precisar de mais
detalhe (seeds, worktrees, etc.):

```bash
# Setup
bundle install && pnpm install

# Rodar localmente
pnpm dev                          # ou: overmind start -f Procfile.dev

# Seeds
bundle exec rails db:seed

# Lint
pnpm eslint          # / pnpm eslint:fix
bundle exec rubocop -a

# Testes
pnpm test             # / pnpm test:watch     (frontend, Vitest)
bundle exec rspec spec/path/to/file_spec.rb          # backend, RSpec
bundle exec rspec spec/path/to/file_spec.rb:LINE     # teste único
```

**RSpec no Docker local**: o container define `RAILS_ENV=development`
(`docker-compose.yaml:42`). O `spec/rails_helper.rb` **força** `ENV['RAILS_ENV'] = 'test'` por
causa disso — antes usava `||=`, que não sobrescrevia, e a suíte inteira rodava contra o
`chatwoot_dev` (falhando só onde algum spec contava linhas globalmente, e silenciosamente no
resto). Se o banco de teste estiver atrás das migrations:

```bash
docker exec -e RAILS_ENV=test chatwoot-noble-rails-1 bundle exec rails db:migrate
docker exec chatwoot-noble-rails-1 bundle exec rspec spec/caminho/do/arquivo_spec.rb
```

---

## 7. Checklist para implementar uma feature nova

Baseado no fluxo real observado neste repo (ex.: como Kanban/Pipeline foi construído) +
`claude/05-novas-funcionalidades.md`, que tem a receita completa passo a passo.

**Onde colocar cada arquivo (backend)**
- Model novo → `app/models/`, sempre `belongs_to :account` se for tenant-scoped, uniqueness
  `scope: :account_id`
- Regra de negócio fora do model → `app/services/<namespace>/<verbo>_service.rb`,
  `#perform` público
- Reação a evento → `app/listeners/`, herdar de `BaseListener`, registrar em
  `config/initializers/event_handlers.rb`
- Trabalho assíncrono → `app/jobs/`, `queue_as` explícito
- Autorização → `app/policies/`, herdar de `ApplicationPolicy`
- Resposta JSON → `app/views/api/.../*.json.jbuilder` (não criar serializer)
- Endpoint novo → documentar em Swagger (YAML com tag correta + registrar em
  `paths/index.yml` + `bundle exec rails swagger:build`) antes de considerar pronto

**Onde colocar cada arquivo (frontend)**
- Chamada HTTP → `app/javascript/dashboard/api/<recurso>.js`, `class XyzAPI extends
  ApiClient`, export singleton
- Estado compartilhado → `store/modules/<feature>/` (Vuex, é o padrão ainda dominante);
  considerar Pinia (`stores/`) só se for algo pequeno e novo, seguindo o padrão de
  `stores/calls.js`
- Lógica reutilizável sem estado → `composables/`
- UI nova → `components-next/` de preferência, `<script setup>`, props/emits em runtime
  (não TS)
- Página nova → `routes/dashboard/<feature>/` com `routes.js` próprio

**Testes**
- Não escrever specs a menos que peçam explicitamente (regra do `AGENTS.md`) — quando pedido:
  RSpec (model + request) no backend com FactoryBot; Vitest colocado junto do arquivo no
  frontend
- Se adicionar/mudar endpoint de API: manter Swagger em dia **e** pôr
  `expect(response).to conform_schema(200)` no exemplo de sucesso — sem o matcher o Skooma não
  verifica nada (ver seção 3)

**i18n**
- Só editar `en.yml`/`en.json` — **exceto** se for feature própria do fork
  (Kanban/Pipeline, Tasks, funil), que mantém `pt_BR` junto; ver seção 3

**Enterprise**
- Ao mexer em lógica core existente, checar se há override/extensão correspondente em
  `enterprise/` e manter os dois sincronizados (`prepend_mod_with`/`include_mod_with`) — é
  código nosso, não uma barreira de plano pago

**Evitar**
- CSS customizado, scoped ou inline — só Tailwind (`AGENTS.md`)
- Defensive programming não justificado / guards sem caso de uso comprovado em produção
- Duplicar lógica entre services parecidos — usar um concern compartilhado (padrão já usado
  em `app/services/concerns/pipeline_item_actions.rb`, incluído por 3 services diferentes)
- Assumir que todo componente já é Composition API — checar o arquivo primeiro
- Inventar padrão "de como o Chatwoot faz" sem checar o código real deste repo — ele diverge
  bastante do upstream em várias áreas
