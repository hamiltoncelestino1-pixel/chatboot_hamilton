# 04 — White-label (Marca / Aparência)

A maior parte do branding do Chatwoot é **configuração, não código** — o que torna o
white-label de baixo risco e bom ponto de partida.

> **Histórico real:** O rebrand completo da Noble Company está documentado task a task em
> `claude/white-label/` (tasks `01` a `07`). Use como referência para futuros rebrands.

---

## 1. Nome, logo e URLs — `config/installation_config.yml`

Seção `Branding Related Config`. Chaves principais:

| Chave | O que controla | Valor Noble Company |
|---|---|---|
| `INSTALLATION_NAME` | Nome da instalação (título da aba, emails) | `Noble Company` |
| `BRAND_NAME` | Nome da marca exibido na UI | `Noble Company` |
| `BRAND_URL` | Link da marca | `https://noblecompany.digital` |
| `WIDGET_BRAND_URL` | Link "powered by" no widget | `https://noblecompany.digital` |
| `LOGO` | Logo principal (dashboard, login) | `/brand-assets/logo.png` |
| `LOGO_DARK` | Logo para modo escuro | `/brand-assets/logo_dark.png` |
| `LOGO_THUMBNAIL` | Logo reduzido / ícone interno | `/brand-assets/logo_thumbnail.png` |
| `TERMS_URL` | URL dos termos de serviço | `https://noblecompany.digital/termos-de-uso` |
| `PRIVACY_URL` | URL da política de privacidade | `https://noblecompany.digital/privacidade` |
| `LOGOUT_REDIRECT_LINK` | Para onde redirecionar após logout | — |

> **Atenção:** `installation_config.yml` é um arquivo de seed — só popula o banco na
> primeira execução. Mudanças posteriores exigem atualizar os registros de `InstallationConfig`
> diretamente no banco via Rails runner:
>
> ```ruby
> InstallationConfig.find_by(name: 'LOGO').update!(value: '/brand-assets/logo.png')
> ```
>
> Os valores também são editáveis em runtime pelo painel **Super Admin → App Configs**.

---

## 2. Arquivos de logo — `public/brand-assets/`

A Noble Company usa **PNG** (não SVG — o designer entregou só PNG):

- `public/brand-assets/logo.png` — logo principal (fundo claro)
- `public/brand-assets/logo_dark.png` — logo para modo escuro
- `public/brand-assets/logo_thumbnail.png` — versão reduzida / ícone

Substitua mantendo os mesmos nomes de arquivo. O `<img>` do Vue aceita PNG diretamente.

---

## 3. Favicons e ícones de app — `public/`

Substitua os arquivos PNG mantendo os mesmos nomes e dimensões:

| Arquivo | Dimensão |
|---|---|
| `public/favicon.ico` | multi-size |
| `public/favicon-16x16.png` | 16×16 |
| `public/favicon-32x32.png` | 32×32 |
| `public/favicon-96x96.png` | 96×96 |
| `public/apple-touch-icon.png` | 180×180 |
| `public/apple-touch-icon-precomposed.png` | 180×180 |
| `public/android-icon-192x192.png` | 192×192 |

Fonte de geração: [favicon.io](https://favicon.io) ou similar a partir do PNG da logo.

---

## 4. Manifest — `public/manifest.json`

```json
{
  "name": "Noble Company",
  "short_name": "Noble",
  "background_color": "#E0203E",
  "theme_color": "#E0203E"
}
```

---

## 5. Cores e tema — Noble Red `#E0203E`

O rebrand substitui o azul padrão do Chatwoot (`#2781F6`) pelo vermelho da Noble (`#E0203E`).
São **dois lugares** que precisam estar em sincronia:

### 5a. Tokens CSS — `app/javascript/dashboard/assets/scss/_noble-brand.scss`

Sobrescreve as variáveis `--blue-*` definidas em `_next-colors.scss`. Importado em `_woot.scss`.
Contém a escala completa de 12 passos do vermelho (claro e escuro) + aliases de borda/texto.

### 5b. Tailwind hex — `theme/colors.js` linha ~231

```js
brand: '#E0203E',
```

Deve sempre bater com `--blue-9` do SCSS. Usado por `n-brand` em ~96 arquivos Vue.

---

## 6. Cores dos emails — templates Liquid/ERB

Os templates de email têm cores hardcoded (não usam o sistema de tokens do dashboard):

- `app/views/layouts/mailer/base.liquid` — accent-bar, links, rodapé
- `app/views/devise/mailer/_confirmation_body.html.erb` — botão CTA, link inline

Busque por `#D4AF37` (dourado Mazza) e substitua por `#E0203E`. Também troque fallbacks
de nome de marca (`'Mazza Advocacia'` → `'Noble Company'`).

---

## 7. Textos "Chatwoot" na interface

Strings visíveis ficam nas traduções — **atualizar apenas `en` (en.yml / en.json)**,
conforme AGENTS.md ("Only update `en.yml` and `en.json`, other languages are handled by the community").

- Frontend dashboard: `app/javascript/dashboard/i18n/locale/en/*.json`
- Widget: `app/javascript/widget/i18n/locale/en.json`
- Survey/CSAT: `app/javascript/survey/i18n/locale/en.json`
- Backend/emails: `config/locales/en.yml`

---

## Checklist de verificação final

- [ ] **Login/Signup**: logo NC (claro e escuro) e título "Noble Company" corretos
- [ ] **Dashboard modo claro**: botões primários/outline em vermelho; sem dourado (`#D4AF37`)
- [ ] **Dashboard modo escuro**: mesma checagem com `.dark`
- [ ] **Ícone pequeno** (sidebar/header): `logo_thumbnail.png` da Noble
- [ ] **Favicon** (aba do navegador): ícone NC, não o Chatwoot padrão
- [ ] **Widget embedado**: "Powered by Noble Company" no rodapé
- [ ] **Preview do widget** no dashboard: consistente com o widget real
- [ ] **Email transacional** (ex.: convite de agente): accent-bar vermelho, rodapé "Noble Company"
- [ ] **Super Admin → App Configs → Branding**: todos os valores da Noble Company
- [ ] **i18n**: `rg -i "chatwoot|mazza" app/javascript/dashboard/i18n/locale/en config/locales/en.yml` → zero resultados
- [ ] **Labels/tags de contato**: cores roxo/violeta do usuário intactas (sem regressão)
- [ ] `pnpm eslint` e `bundle exec rubocop -a` limpos
