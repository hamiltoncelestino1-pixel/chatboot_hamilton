# Task: Varredura de textos "Chatwoot" residuais

## Objetivo

Trocar strings literais "Chatwoot" visíveis na UI por "Noble Company" (ou "Noble", conforme o
contexto). Como o uso é **interno** (uma marca só), a troca é direta — não é necessário
depender de `useBranding`/`replaceInstallationName` para esses pontos (esse composable já
existe e continua funcionando nos lugares onde já está integrado, ex.
`shared/components/Branding.vue`, sem necessidade de mudança nesta task).

---

## 1. Backend — `config/locales/en.yml`

~4 ocorrências, todas em descrições de integrações (Dyte, Slack, Webhooks), por volta das
linhas 336, 337, 342, 345. Revisar cada uma e trocar "Chatwoot" por "Noble Company" quando a
frase descreve a própria instalação (não trocar se for uma referência necessária ao produto
Chatwoot em si, ex. texto legal/atribuição — confirmar caso a caso).

## 2. Frontend dashboard — `app/javascript/dashboard/i18n/locale/en/*.json`

Arquivos com "Chatwoot" encontrados na varredura:

- `auditLogs.json` (2 ocorrências)
- `conversation.json` (1)
- `generalSettings.json` (4)
- `helpCenter.json` (5)
- `inboxMgmt.json` (7)
- `integrations.json` (6)
- `labelsMgmt.json` (1)
- `mfa.json` (1)
- `resetPassword.json` (1)
- `settings.json` (3)
- `signup.json` (2)
- `yearInReview.json` (2)

Trocar "Chatwoot" por "Noble Company" em cada uma, revisando o contexto da frase (algumas
podem precisar de ajuste além da simples substituição de palavra, ex. concordância).

## 3. Widget e Survey — chave `POWERED_BY`

- `app/javascript/widget/i18n/locale/en.json:60` → `"Powered by Chatwoot"` →
  `"Powered by Noble Company"`
- `app/javascript/survey/i18n/locale/en.json:18` → mesma troca

Os demais ~55 arquivos de locale (não-inglês) por idioma **ficam de fora** — comunidade
mantém as traduções, conforme já documentado em `AGENTS.md` ("Only update `en.yml` and
`en.json`, other languages are handled by the community").

## 4. Componentes Vue com "Chatwoot" hardcoded fora de i18n

Revisar e trocar (ou mover para i18n, se fizer sentido) nos seguintes arquivos:

- `app/javascript/dashboard/store/utils/api.js`
- `app/javascript/v3/views/login/Saml.vue`
- `app/javascript/v3/views/auth/signup/Index.vue`
- `app/javascript/dashboard/routes/dashboard/settings/integrations/MultipleIntegrationHooks.vue`
- `app/javascript/dashboard/components/widgets/conversation/OnboardingView.vue`

---

## Verificação

- Rodar `rg -i "chatwoot" config/locales/en.yml app/javascript/dashboard/i18n/locale/en
  app/javascript/widget/i18n/locale/en.json app/javascript/survey/i18n/locale/en.json` depois
  das edições — não deve sobrar nenhuma ocorrência (exceto onde decidido manter por ser
  atribuição legal/técnica ao produto Chatwoot, se houver).
- Rodar `pnpm eslint` para garantir que os JSONs/Vue continuam válidos.
- Navegar pelas telas afetadas (signup, configurações gerais, integrações, central de ajuda,
  widget, survey CSAT) e conferir visualmente os textos trocados.
