# 06 — Integrações Externas

Como o Chatwoot conecta a serviços de terceiros, canais de mensagem e IA.

## 1. Integrações de "app" (Slack, Dialogflow, OpenAI...)

- **Registro**: `config/integration/apps.yml` — declara quais integrações existem,
  campos de configuração e metadados.
- **Código**: `lib/integrations/<servico>/` — implementação. Modelos para copiar:
  - `lib/integrations/slack/`
  - `lib/integrations/openai/`
  - `lib/integrations/dialogflow/`
  - `lib/integrations/google_translate/`
- **Controllers**: `app/controllers/api/v1/accounts/integrations/` expõem a configuração
  ao dashboard.

## 2. Canais de mensagem (WhatsApp, Email, Instagram, Telegram...)

Um **canal** é como o cliente conversa. Para um canal funcionar:
- **Model**: `app/models/channel/<canal>.rb` — guarda credenciais/config.
- **Inbox**: um `inbox` aponta para um canal; é a unidade configurável pelo usuário.
- **Service de envio**: `app/services/<canal>/` — monta e envia mensagens.
- **Webhook de entrada**: `app/controllers/webhooks/` — recebe mensagens do provedor.
- **Jobs**: `app/jobs/` — processamento assíncrono (mídia, status de entrega).

Fluxo de uma mensagem recebida:
```
provedor externo → webhook controller → builder (cria contato/conversa/mensagem)
   → dispatcher (evento) → listener (notifica) → ActionCable (push ao agente)
```

## 3. IA / LLM

- `config/llm.yml` e `config/llm_models.json` — modelos e configuração de IA.
- `lib/llm/` — clientes e helpers de LLM.
- `lib/captain/` e `lib/integrations/captain/` — o assistente "Captain" do Chatwoot.
- Recursos avançados de IA costumam viver em `enterprise/` também.

> Observação: ao construir recursos de IA próprios, prefira os modelos Claude mais
> recentes (Opus/Sonnet/Haiku da família 4.x). Veja a documentação da Claude API antes
> de fixar IDs de modelo.

## 4. Webhooks de saída (eventos para sistemas externos)

- Configuráveis por conta; disparados por `app/listeners/` quando eventos ocorrem.
- Código de entrega em `lib/webhooks/`.

## Checklist de verificação
1. Nova integração de app: aparece em **Configurações → Integrações** no dashboard.
2. Novo canal: criar inbox, enviar e receber uma mensagem de ponta a ponta.
3. Webhook: usar um endpoint de teste (ex.: webhook.site) e confirmar o payload.
