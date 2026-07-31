# Guia de Customização — Chatwoot Noble

Documentação interna para construir e manter nossa **versão personalizada do Chatwoot**
(base: **v4.13.0**). Use estes arquivos como referência principal de "onde mexer".

## Stack em uma frase

API JSON em **Ruby on Rails** (`app/`) consumida por várias SPAs **Vue.js** compiladas
pelo **Vite** (`app/javascript/`), com tarefas assíncronas (Sidekiq), tempo real
(ActionCable) e recursos premium isolados em `enterprise/`.

```
Backend (Rails)  →  app/ (Ruby) + config/ + lib/ + db/
Frontend (Vue)   →  app/javascript/ (compilado por Vite)
Enterprise       →  enterprise/ (espelha app/ com recursos premium)
```

## Índice

| Arquivo | Conteúdo |
|---|---|
| [01-estrutura-do-projeto.md](01-estrutura-do-projeto.md) | Mapa completo de pastas e arquivos da raiz e de `app/` |
| [02-backend-rails.md](02-backend-rails.md) | Como funciona o backend: models, controllers, services, jobs, eventos |
| [03-frontend-vue.md](03-frontend-vue.md) | As SPAs Vue: dashboard, widget, portal e como o estado/rotas funcionam |
| [04-white-label.md](04-white-label.md) | Guia de marca/aparência: logo, nome, cores, textos |
| [05-novas-funcionalidades.md](05-novas-funcionalidades.md) | Receita full-stack para adicionar uma feature do banco até a tela |
| [06-integracoes.md](06-integracoes.md) | Integrações externas, canais, webhooks e IA/LLM |
| [07-enterprise.md](07-enterprise.md) | Como a camada `enterprise/` estende o core |
| [08-ambiente-local-docker.md](08-ambiente-local-docker.md) | Rodar localmente no Docker + gotchas já resolvidos (RAM/WSL2, CRLF, Postgres) |
| [09-deploy-producao.md](09-deploy-producao.md) | Levar nossa versão para o servidor: build da imagem, registry, compose de produção |
| [10-fluxo-git.md](10-fluxo-git.md) | Fluxo de Git em equipe: branches, commits, Pull Requests e como evitar conflitos |

## Históricos de implementação (tasks passo a passo)

Pastas com tasks numeradas (`NN-tipo-descricao.md`) documentando, em detalhe, ciclos de
trabalho já concluídos ou em andamento — úteis como exemplo real para quem for fazer algo
parecido no futuro:

| Pasta | Conteúdo |
|---|---|
| [white-label/](white-label/) | Rebrand completo para Noble Company (cores, assets, i18n) |
| [pipeline_tasks/](pipeline_tasks/) | Melhorias no Pipeline/Kanban de oportunidades: filtro geral, ordenação, datas fixas no card, exportar (transferir) card entre pipelines, ajuste de policy para agentes verem todas as oportunidades; e o épico atual — macros/automações aplicáveis a pipelines e regra de 1 card por contato por pipeline (ver [00-visao-geral.md](pipeline_tasks/00-visao-geral.md)) |
| [assignment_tasks/](assignment_tasks/) | Atribuição automática de conversas por demanda (least-busy) além do rodízio, fim da regra "só agente online" e fallback anti-silêncio de capacidade/rate-limit (ver [00-visao-geral.md](assignment_tasks/00-visao-geral.md)) |
| [premium_unlock_tasks/](premium_unlock_tasks/) | Remoção da trava de reset noturno que desligava features premium e resetava o branding pro padrão Chatwoot (ping pro hub da Chatwoot + `ReconcilePlanConfigService`) — ver [00-visao-geral.md](premium_unlock_tasks/00-visao-geral.md) |

## Arquivos-chave para conhecer primeiro

- `config/routes.rb` — mapa de todas as URLs → controllers.
- `config/installation_config.yml` — configuração global e branding.
- `config/features.yml` — feature flags (ligar/desligar funcionalidades).
- `app/models/account.rb`, `conversation.rb`, `contact.rb`, `inbox.rb` — entidades centrais.
- `app/javascript/dashboard/App.vue` + `routes/dashboard/` — entrada do frontend principal.

## Como subir o ambiente (referência rápida)

- Dev local: processos definidos em `Procfile.dev` (web Rails + worker Sidekiq + Vite).
- Docker: `docker-compose.yaml` (dev) / `docker-compose.production.yaml`.
- Testes: `spec/` (RSpec) espelha a estrutura de `app/`.
