# Task: Substituir assets visuais (logo, favicons, manifest)

## Objetivo

Trocar os arquivos de imagem que ainda carregam a identidade visual da Mazza Advocacia
(logo com o texto "MAZZA"/"ADVOCACIA" em dourado) pelos arquivos finais da Noble Company
(já prontos — não é necessário gerar arte nova nesta task).

---

## 1. Logos principais — `public/brand-assets/`

Substituir o **conteúdo** dos três arquivos abaixo, mantendo exatamente os mesmos nomes
(são referenciados por caminho fixo em `config/installation_config.yml`, task
`03-chore-installation-config-noble.md`):

- `public/brand-assets/logo.svg` — hoje é um wordmark "MAZZA" serifado com borda/texto
  dourado (`#D4AF37`). Trocar pela logo "NC" da Noble (versão clara).
- `public/brand-assets/logo_dark.svg` — mesma logo, variante para modo escuro (hoje dourado
  claro `#F0CE6A`).
- `public/brand-assets/logo_thumbnail.svg` — hoje 512×512 com fundo dourado e "M" branco.
  Trocar pelo ícone "NC" quadrado da Noble (usado como favicon interno e como marca
  "Powered by" no widget/portal — ver `app/javascript/shared/components/Branding.vue`).

## 2. Favicons e ícones de app — `public/`

Substituir mantendo os mesmos nomes/dimensões (usados em `app/views/layouts/vueapp.html.erb`
quando `DISPLAY_MANIFEST` estiver habilitado, e por navegadores/PWA diretamente):

- `favicon-16x16.png`, `favicon-32x32.png`, `favicon-96x96.png`, `favicon-512x512.png`,
  `favicon-badge-*.png`
- `apple-icon*.png`, `apple-touch-icon*.png` (todos os tamanhos existentes)
- `android-icon-36x36.png`, `-48x48.png`, `-72x72.png`, `-96x96.png`, `-144x144.png`,
  `-192x192.png`
- `ms-icon-*.png`

## 3. `public/manifest.json`

Hoje (linhas 1-3, 42-43):

```json
{
  "name": "Chatwoot",
  "short_name": "Chatwoot",
  ...
  "background_color": "#1f93ff",
  "theme_color": "#1f93ff"
}
```

Trocar para:

```json
{
  "name": "Noble Company",
  "short_name": "Noble",
  ...
  "background_color": "#E0203E",
  "theme_color": "#E0203E"
}
```

> Usar o mesmo hex de vermelho definido em `01-chore-noble-color-tokens.md` (`--blue-9`) para
> `background_color`/`theme_color`. Este arquivo é estático — não é lido de
> `installation_config.yml`.

## 4. Fallback inline do ícone pequeno — `Logo.vue`

Arquivo: `app/javascript/dashboard/components-next/icon/Logo.vue:15-42`

Hoje, quando `globalConfig.logoThumbnail` está vazio, renderiza um SVG inline com o azul do
Chatwoot (`fill="#2781F6"`) formando um "C". Na prática isso não deveria disparar (o config
sempre define `LOGO_THUMBNAIL`), mas por correção/consistência, trocar o `fill="#2781F6"`
pelo vermelho da Noble (mesmo hex de `--blue-9`) — ou, se for mais simples, desenhar um "NC"
minimalista no lugar do "C" atual.

---

## Verificação

- Abrir a tela de login (`/`) e conferir o novo logo em modo claro e escuro.
- Abrir o dashboard e conferir o ícone pequeno no header/sidebar.
- Abrir um widget de teste e a Central de Ajuda (se houver) e conferir o "Powered by" com o
  novo `logo_thumbnail.svg`.
- Verificar aba do navegador (favicon) e, se for testar instalação como PWA, o ícone/nome
  vindos de `manifest.json`.
