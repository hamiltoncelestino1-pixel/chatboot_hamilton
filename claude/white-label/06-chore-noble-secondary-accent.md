# Task: Roxo escuro como cor auxiliar (destaque decorativo)

## Objetivo

Aplicar o roxo escuro definido como cor auxiliar da Noble (o laranja da logo fica só na
marca — não vira cor de UI) em pontos decorativos pontuais, **sem** sobrescrever tokens
sistêmicos que já são usados para outra finalidade.

---

## Por que isso é uma task separada e "à parte"

Diferente do vermelho primário (`01-chore-noble-color-tokens.md`), que substitui um token
sistêmico (`--blue-*` / `n.brand`) usado em botões/links em 96+ arquivos, o roxo **não** tem
um slot sistêmico livre para ocupar:

- `n.violet` / `n.iris` (definidos em `theme/colors.js` e `_next-colors.scss`) já são usados
  hoje como cores arbitrárias de labels/tags de contato e outras seleções de cor do usuário —
  não são tokens de branding. Sobrescrever esses valores mudaria a aparência de dados criados
  pelos usuários (labels existentes), o que é uma regressão, não uma melhoria de marca.

Por isso, o roxo deve ser introduzido como um **acento visual pontual**, não como substituição
de um token global.

## 1. Fundo/gradiente das telas de autenticação

Arquivos:

- `app/javascript/v3/views/login/Index.vue`
- `app/javascript/v3/views/auth/signup/Index.vue`

Adicionar um fundo/gradiente decorativo (ex.: um degradê sutil do vermelho primário para o
roxo escuro, no estilo do que a logo faz do vermelho para o laranja, mas trocando laranja por
roxo) atrás do card de login/signup. Definir o hex do roxo como uma constante local nesses
componentes (ou uma nova CSS var dedicada, ex. `--noble-accent-purple`, se for reaproveitar em
mais de um lugar) — não reaproveitar `--violet-*`/`--iris-*` existentes.

Sugestão de ponto de partida para o roxo (ajustar visualmente): `#4A1D4F` (roxo escuro/vinho,
harmoniza com o vermelho `#E0203E` sem competir com ele).

## 2. Outros candidatos opcionais (avaliar durante a implementação)

- Tela de onboarding (`v3/views/onboarding/OnboardingStep.vue`), se fizer sentido visualmente.
- Preview do widget no dashboard (`dashboard/modules/widget-preview/components/Widget.vue`),
  apenas como decoração de fundo do preview — não a cor funcional do widget do cliente.

Não obrigatório: se o roxo não encaixar bem em nenhum lugar durante a implementação visual,
está OK reduzir o escopo desta task só para o fundo de login/signup.

## O que explicitamente NÃO fazer aqui

- Não sobrescrever `--violet-*` ou `--iris-*` em `_next-colors.scss`.
- Não tocar nas opções de cor de labels/tags de contato.
- Não misturar o roxo com os botões primários/outline (isso é escopo da task `01`, que já
  fixa vermelho + branco para essa combinação).

---

## Verificação

- Abrir a tela de login e signup e conferir visualmente o novo acento roxo.
- Conferir que labels/tags de contato existentes que usam roxo/violeta continuam com a cor
  original (nenhuma regressão).
- Testar em modo claro e escuro.
