# 04 — White-label (Marca / Aparência)

A maior parte do branding do Chatwoot é **configuração, não código** — o que torna o
white-label de baixo risco e bom ponto de partida.

## 1. Nome, logo e URLs — `config/installation_config.yml`

Seção `Branding Related Config`. Chaves principais:

| Chave | O que controla |
|---|---|
| `INSTALLATION_NAME` | Nome da instalação (aparece no título, emails) |
| `BRAND_NAME` | Nome da marca exibido na UI |
| `BRAND_URL` | Link da marca |
| `WIDGET_BRAND_URL` | Link "powered by" no widget |
| `LOGO` | Logo principal (dashboard, login) |
| `LOGO_DARK` | Logo para modo escuro |
| `LOGO_THUMBNAIL` | Logo reduzido / favicon interno |
| `TERMS_URL` | URL dos termos de serviço (signup) |
| `PRIVACY_URL` | URL da política de privacidade |
| `LOGOUT_REDIRECT_LINK` | Para onde redirecionar após logout |

> Esses valores também são editáveis em **runtime** pelo painel Super Admin
> (sem recompilar). O `installation_config.yml` define apenas os padrões.

## 2. Arquivos de logo — `public/brand-assets/`

Substitua diretamente:
- `public/brand-assets/logo.svg`
- `public/brand-assets/logo_dark.svg`
- `public/brand-assets/logo_thumbnail.svg`

## 3. Favicons e ícones de app — `public/`

Ícones PNG por tamanho: `apple-icon-*.png`, `android-icon-*.png`, etc. Substitua mantendo
os mesmos nomes/dimensões.

## 4. Cores e tema

- Dashboard: `app/javascript/dashboard/assets/` e `app/javascript/design-system/`
  (Tailwind + SCSS).
- Widget: `app/javascript/widget/assets/`.
- Ajuste as cores primárias/tema no tema Tailwind e nos tokens do design-system.

## 5. Textos "Chatwoot" na interface

Strings visíveis ficam nas traduções:
- Frontend: `app/javascript/dashboard/i18n/` (e `widget/i18n/`, `survey/i18n/`).
- Backend (emails, etc.): `config/locales/`.

Procure por menções a "Chatwoot" e troque pela marca Noble onde fizer sentido.

## Checklist de verificação
1. Trocar logo + `INSTALLATION_NAME` e abrir a **tela de login** → ver novo logo/nome.
2. Entrar no **dashboard** → conferir logo no header e modo escuro.
3. Abrir o **widget** num site de teste → conferir branding/"powered by".
4. Disparar um **email** (ex.: convite de agente) → conferir remetente/marca.
