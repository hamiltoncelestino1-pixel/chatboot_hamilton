# 02 — Backend (Ruby on Rails)

O backend é um monólito Rails que expõe uma API JSON e processa eventos em tempo real e
em background. As camadas seguem um padrão consistente.

## Fluxo de uma requisição típica

```
HTTP → config/routes.rb → controller (app/controllers/api/v1/...)
     → policy (autorização) → service (lógica) → model (dados)
     → dispatcher/listener (eventos) → job (assíncrono) → channel (tempo real)
```

## Camadas e responsabilidades

### `app/models/` — dados e regras
Cada arquivo é uma tabela/entidade. Validações, associações e regras simples vivem aqui.
- Centrais: `account.rb` (conta/empresa), `conversation.rb`, `contact.rb`,
  `inbox.rb` (canal configurado), `message.rb`, `user.rb`.
- `channel/` — um model por tipo de canal (ex.: `channel/whatsapp.rb`, `channel/email.rb`,
  `channel/web_widget.rb`). Um `inbox` aponta para um desses canais.
- `concerns/` — módulos compartilhados entre models.

### `app/controllers/` — entrada HTTP
- `api/v1/accounts/` — a maioria dos endpoints do dashboard (escopo por conta).
- `api/v2/` — versão mais recente de alguns endpoints.
- `public/` — API pública (widget, portal).
- `platform/` — API de administração de plataforma.
- `super_admin/` — painel administrativo (Administrate).
- `webhooks/` — recebem callbacks de serviços externos (Meta, Twilio...).
- Controllers são finos: validam, autorizam e delegam para um **service**.

### `app/services/` — lógica de negócio (onde mais se customiza)
Organizado por domínio. Exemplos:
- `conversations/` — criar, atribuir, resolver conversas.
- `contacts/` — merge, importação, etc.
- `messages/` — montar e enviar mensagens por canal.
- `automation_rules/` — motor de automação.
- `auto_assignment/` — distribuição de conversas entre agentes.
- `filters/`, `filter_service.rb` — busca avançada.

### Eventos e assíncrono
- `app/dispatchers/` — publicam eventos do domínio (ex.: `conversation.created`).
- `app/listeners/` — assinam eventos e reagem (notificar, gerar webhook, atualizar contadores).
- `app/jobs/` — trabalho pesado fora do ciclo da requisição (Sidekiq). Ex.: envio de email,
  sincronização com canais, processamento de mídia.
- `app/channels/` — ActionCable (WebSocket) para push em tempo real ao frontend.

### Autorização e suporte
- `app/policies/` — Pundit. Define permissões por papel (admin, agente).
- `app/builders/` — criam grafos de objetos complexos numa transação.
- `app/finders/` — encapsulam queries de listagem/filtro.
- `app/presenters/` / `app/drops/` — formatam dados (Liquid usado em templates de mensagem).
- `app/mailers/` / `app/mailboxes/` — saída e entrada de email.

## Banco de dados
- Toda mudança de schema = nova migração em `db/migrate/`.
- `db/schema.rb` é gerado automaticamente — **não editar à mão**.
- Para popular dados de teste: `db/seeds.rb` e `lib/seeders/`.

## Dicas de customização
- Prefira adicionar lógica em **services** novos a inchar models/controllers.
- Antes de criar algo, procure um service/finder/builder existente que já faça parte do
  trabalho — o projeto reaproveita muito.
- Mudanças que disparam efeitos colaterais geralmente passam por dispatcher → listener.
