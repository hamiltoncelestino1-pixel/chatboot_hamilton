# 03 — Frontend (Vue.js / Vite)

`app/javascript/` contém **várias aplicações Vue separadas**, cada uma com um público e
propósito diferente. Todas são compiladas pelo Vite (`vite.config.ts`).

## As aplicações

| Pasta | Para quem | Responsabilidade |
|---|---|---|
| **`dashboard/`** | Agente / Admin | App principal — atender conversas, configurar conta. **Maior parte da UI** |
| **`widget/`** | Visitante do site | Chat embutido no site do cliente final |
| **`portal/`** | Público | Central de ajuda / base de conhecimento |
| **`survey/`** | Cliente final | Tela de pesquisa de satisfação (CSAT) |
| **`v3/`** | — | Nova versão da interface (migração em andamento) |
| **`shared/`** | — | Componentes, helpers e mixins reutilizados entre apps |
| **`design-system/`** | — | Biblioteca de componentes de UI reutilizáveis |
| **`superadmin_pages/`** | Super Admin | Scripts da área administrativa |

## Dentro de `dashboard/` (onde mais se mexe na UI)

| Subpasta | Responsabilidade |
|---|---|
| `App.vue` | Componente raiz da aplicação |
| `components/` | Componentes Vue (geração atual): `ChatList.vue`, `ConversationItem.vue`, `Modal.vue`... |
| `components-next/` | Componentes da nova geração (refatoração) |
| `routes/dashboard/` | Define páginas/rotas e qual componente carregar em cada URL |
| `store/modules/` | **Vuex** — estado global (conversas, contatos, agentes em memória no navegador) |
| `api/` | Funções que chamam a API do backend (uma por domínio) |
| `modules/` | Funcionalidades agrupadas por domínio |
| `i18n/` | Traduções da interface |
| `assets/` | SCSS, imagens, estilos |

## Fluxo de dados no frontend

```
Componente (.vue)
   ↓ dispara action
store/modules/<dominio> (Vuex)
   ↓ chama
api/<dominio>.js
   ↓ HTTP
Backend Rails (API)
   ↓ retorno + push via WebSocket (ActionCable)
store atualiza estado → componentes re-renderizam
```

## Receita para mexer na UI do dashboard

1. Localize a **rota** em `routes/dashboard/` para achar o componente da página.
2. Edite o **componente** em `components/` ou `components-next/`.
3. Se precisar de dados novos, ajuste o **módulo Vuex** em `store/modules/` e a
   função em `api/`.
4. Textos visíveis vão em `i18n/` (nunca hardcode strings — use as chaves de tradução).
5. Estilos em `assets/` (Tailwind + SCSS).

## Build
- `vite.config.ts` controla a compilação e os entrypoints de cada app.
- Em dev, o Vite roda como processo separado (ver `Procfile.dev`) com hot reload.
