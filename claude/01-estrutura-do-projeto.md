# 01 — Estrutura do Projeto

Mapa de pastas e arquivos. Comece por aqui para se orientar.

## Raiz do projeto — configuração e infraestrutura

| Arquivo/Pasta | Responsabilidade |
|---|---|
| `Gemfile` / `Gemfile.lock` | Dependências Ruby (gems do backend) |
| `package.json` / `pnpm-lock.yaml` | Dependências JavaScript (frontend) |
| `vite.config.ts` | Configuração do bundler que compila o Vue |
| `Procfile*` | Define os processos (web, worker, vite) para rodar a app |
| `docker-compose*.yaml` / `docker/` | Containerização e deploy |
| `VERSION_CW` | Versão do Chatwoot (**4.13.0**) |
| `Makefile` / `Rakefile` | Atalhos de comandos e tarefas |
| `README.md`, `AGENTS.md`, `CLAUDE.md` | Documentação do projeto |
| `app/` | Coração da aplicação (backend Rails + frontend Vue) |
| `config/` | Configuração do Rails, rotas, integrações, traduções |
| `lib/` | Código utilitário e integrações de baixo nível |
| `db/` | Migrações, schema e seeds do banco |
| `enterprise/` | Recursos premium que estendem o core |
| `spec/` | Testes automatizados (RSpec) |
| `public/` | Arquivos estáticos servidos diretamente (logos, favicons) |
| `swagger/` | Documentação da API (OpenAPI) |
| `script/` / `bin/` | Scripts de automação e executáveis |

## `app/` — backend Rails (MVC) + frontend

| Pasta | Responsabilidade |
|---|---|
| **`models/`** | Entidades de negócio e regras de dados. Centrais: `account.rb`, `conversation.rb`, `contact.rb`, `inbox.rb`, `message.rb`, `user.rb`. `channel/` define cada tipo de canal (WhatsApp, Email, WebWidget...) |
| **`controllers/`** | Recebem requisições HTTP. `api/v1/` e `api/v2/` são as APIs que o frontend consome; `public/`, `platform/`, `super_admin/` são outras superfícies |
| **`services/`** | **Camada de lógica de negócio** — o trabalho pesado. Organizado por domínio: `conversations/`, `contacts/`, `messages/`, `automation_rules/`, integrações |
| **`javascript/`** | Todo o **frontend Vue.js** (ver [03-frontend-vue.md](03-frontend-vue.md)) |
| **`jobs/`** | Tarefas assíncronas (background) processadas pelo Sidekiq |
| **`listeners/`** + **`dispatchers/`** | Sistema de eventos: reagem a acontecimentos e disparam notificações/webhooks |
| **`builders/`** | Montam objetos complexos (ex.: contato + conversa + mensagem juntos) |
| **`finders/`** | Lógica de busca/filtragem de registros |
| **`policies/`** | Autorização — quem pode fazer o quê (Pundit) |
| **`mailers/`** + **`mailboxes/`** | Envio e recebimento de emails |
| **`views/`** | Templates do servidor (emails, telas admin, layout base) |
| **`presenters/`** / **`drops/`** | Formatação de dados e variáveis de template (Liquid) |
| **`channels/`** | WebSockets (ActionCable) — atualizações em tempo real |
| **`dashboards/`** / **`fields/`** | Configuração do painel administrativo (Administrate) |

## `config/`, `lib/`, `db/`

| Item | Responsabilidade |
|---|---|
| `config/routes.rb` | **Mapa de todas as URLs** → controllers |
| `config/initializers/` | Código executado na inicialização (configura gems) |
| `config/features.yml` | Feature flags |
| `config/installation_config.yml` | Configurações globais padrão (inclui branding) |
| `config/locales/` | Traduções do backend |
| `config/integration/apps.yml` | Registro de integrações disponíveis |
| `lib/integrations/` | Código das integrações externas (Slack, OpenAI, Dialogflow...) |
| `lib/llm/`, `lib/captain/` | Recursos de IA |
| `db/migrate/` | Migrações (histórico de mudanças no banco) |
| `db/schema.rb` | Estrutura atual completa do banco (gerado) |
| `db/seeds.rb` | Dados iniciais |
