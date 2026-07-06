# Task: Cor primária Noble (vermelho) nos tokens de design system

## Objetivo

Substituir a escala dourada deixada pelo rebrand anterior (Mazza Advocacia, `#D4AF37`) pela
cor primária da Noble Company (vermelho, base ≈ `#E0203E`) nos dois lugares que controlam a
cor de destaque ("brand") em todo o dashboard novo (`components-next/*`).

Esta task **não** mexe no roxo auxiliar (fica em `06-chore-noble-secondary-accent.md`), nem
em logos/assets (fica em `02-chore-replace-brand-assets.md`).

---

## Contexto importante

A cor de marca vive em **dois lugares que precisam ficar sincronizados**, porque são usados
juntos no mesmo componente:

- `app/javascript/dashboard/assets/scss/_mazza-brand.scss` sobrescreve as CSS vars
  `--blue-1..12` (+ `--border-blue-strong`, `--border-blue`, `--solid-blue`, `--solid-blue-2`,
  `--text-blue`) definidas em `_next-colors.scss`, tanto em `:root` quanto em `.dark`.
- `theme/colors.js` linha 231 define `n.brand: '#D4AF37'` — um hex separado, **não** ligado
  às CSS vars acima.

Em `app/javascript/dashboard/components-next/button/Button.vue:104-107`, o botão primário
usa os dois ao mesmo tempo:

```js
solid: 'bg-n-brand text-white hover:enabled:brightness-110 ...',
subtle: 'bg-n-brand/10 text-n-blue-11 hover:enabled:bg-n-brand/20 ...',
outline: 'text-n-blue-11 outline-n-brand',
```

Ou seja, o botão "outline"/"subtle" combina `n-brand` (do `theme/colors.js`) com `n-blue-11`
(da CSS var `--blue-11`). Essa combinação (`n-brand` + `n-blue-*`) aparece em **96 arquivos /
124 usos** no dashboard — é o botão/destaque primário de todo o design system novo. Os dois
hex têm que ser variações do **mesmo vermelho** para o outline continuar coerente com o solid.

O widget (`app/javascript/widget/assets/scss/woot.scss`) **não** importa `_next-colors.scss`
nem o override de brand — branding de cor lá é irrelevante para esta task (widget usa
`widget_color` por inbox).

---

## 1. Renomear e reescrever `_mazza-brand.scss` → `_noble-brand.scss`

Caminho: `app/javascript/dashboard/assets/scss/_mazza-brand.scss` →
`app/javascript/dashboard/assets/scss/_noble-brand.scss`

Manter exatamente a mesma estrutura (12 tons + aliases), trocando os valores dourados por uma
escala vermelha equivalente (formato `R G B` sem vírgulas, como já está no arquivo). Ponto de
partida sugerido (ajustar tonalidade fina visualmente depois):

```scss
// Noble Company brand overrides
// Replaces Chatwoot blue (#2781F6) with Noble red (#E0203E) across the design system.
// These override the --blue-* CSS variables defined in _next-colors.scss.
@layer base {
  :root {
    --blue-1: 255 247 247;
    --blue-2: 254 235 236;
    --blue-3: 253 214 217;
    --blue-4: 250 186 191;
    --blue-5: 246 150 158;
    --blue-6: 239 108 119;
    --blue-7: 227 76 90;
    --blue-8: 217 45 62;
    --blue-9: 224 32 62;
    --blue-10: 198 24 51;
    --blue-11: 163 15 40;
    --blue-12: 64 8 18;

    --border-blue-strong: 140 15 35;
    --border-blue: 224, 32, 62, 0.5;
    --solid-blue: 250 186 191;
    --solid-blue-2: 255 247 247;
    --text-blue: 90 8 18;
  }

  .dark {
    --blue-1: 30 10 12;
    --blue-2: 46 14 17;
    --blue-3: 70 18 24;
    --blue-4: 94 22 30;
    --blue-5: 116 26 36;
    --blue-6: 140 32 44;
    --blue-7: 166 40 54;
    --blue-8: 194 48 64;
    --blue-9: 224 32 62;
    --blue-10: 235 60 84;
    --blue-11: 245 110 128;
    --blue-12: 254 224 228;

    --border-blue-strong: 245 110 128;
    --border-blue: 224, 32, 62, 0.5;
    --solid-blue: 94 22 30;
    --solid-blue-2: 30 10 12;
    --text-blue: 254 224 228;
  }
}
```

> Os valores acima são um ponto de partida derivado matematicamente do hex `#E0203E`
> (`--blue-9`). Ajustar visualmente contra a logo durante a implementação — o importante é
> preservar a estrutura de 12 passos e os aliases semânticos.

## 2. Atualizar `theme/colors.js`

Linha 231:

```diff
- brand: '#D4AF37',
+ brand: '#E0203E',
```

Usar o **mesmo hex** do `--blue-9` escolhido no passo 1, para o par solid/outline do botão
continuar visualmente coerente.

## 3. Atualizar import em `_woot.scss`

Arquivo: `app/javascript/dashboard/assets/scss/_woot.scss:10-13`

```diff
  @import 'next-colors';

- // Mazza Advocacia brand color overrides (gold theme)
- @import 'mazza-brand';
+ // Noble Company brand color overrides (red theme)
+ @import 'noble-brand';
```

---

## Verificação

- Rodar `pnpm dev`, abrir o dashboard em modo claro e escuro.
- Conferir botões primários (solid), secundários (subtle) e outline em qualquer tela de
  settings — todos devem usar tons do novo vermelho, sem restos de dourado.
- Conferir foco/links que hoje usam `n-blue-*` (ex.: campos de formulário focados).
- Rodar `pnpm eslint` (SCSS/JS não deve quebrar lint por causa do rename de import).
