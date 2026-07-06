# Task: Corrigir cores hardcoded (douradas) nos templates de email

## Objetivo

Os templates de email não usam o sistema de tokens do dashboard — têm o hex dourado
`#D4AF37` (Mazza) hardcoded diretamente no HTML/CSS inline. Trocar pelo vermelho da Noble
(mesmo hex definido em `01-chore-noble-color-tokens.md`, ex. `#E0203E`), e corrigir o
fallback de nome de marca.

---

## 1. `app/views/layouts/mailer/base.liquid`

Ocorrências de `#D4AF37` a trocar por `#E0203E`:

- Linha 30 — cor de link padrão (`a { color: #D4AF37; }`)
- Linha 49 — `.accent-bar { background-color: #D4AF37; }`
- Linha 67 — `.footer a { color: #D4AF37; ... }`
- Linha 108 — `background-color: #D4AF37;` (accent bar, inline style duplicado da classe)
- Linha 125 — `<a href="{{ brand_url }}" style="color: #D4AF37; ...">`

Fallback de nome (linhas 93-96):

```diff
  {% assign brand_name = global_config['BRAND_NAME'] %}
  {% if brand_name == nil %}
-   {% assign brand_name = 'Mazza Advocacia' %}
+   {% assign brand_name = 'Noble Company' %}
  {% endif %}
```

## 2. `app/views/devise/mailer/_confirmation_body.html.erb`

Ocorrências de `#D4AF37` a trocar por `#E0203E`:

- Linha 51 — `bgcolor="#D4AF37"` e `background-color: #D4AF37;` no botão de CTA
- Linha 69 — `color:#D4AF37;` no link "this secure link"

Os demais tons neutros do arquivo (`#0F172A`, `#475569`, `#64748B`, `#DCE7F5`, `#FDF8E7`,
`#8A6500` no badge "eyebrow") não são relacionados à marca e **não** precisam mudar nesta
task, a menos que se decida também alinhar a cor do badge "eyebrow" ao vermelho — se sim,
tratar como ajuste visual opcional, não obrigatório.

## 3. Conferir mailers que herdam o layout

`app/views/devise/mailer/confirmation_instructions.html.erb` e a versão enterprise
(`enterprise/app/views/devise/mailer/confirmation_instructions.html.erb`) usam
`global_config['BRAND_NAME'] || 'Chatwoot'` — como a task `03` já configura `BRAND_NAME` para
"Noble Company", esses arquivos não devem precisar de edição, só conferência visual depois
da task 03 aplicada.

Os mailers Liquid em `app/views/mailers/**/*.liquid` (notificações de admin/agente/time,
convite de portal — ~25 arquivos) herdam `base.liquid`, então devem pegar a cor nova
automaticamente. Fazer uma checagem rápida (grep por `#D4AF37` ou `Mazza`) para confirmar que
nenhum arquivo desse grupo tem cor ou nome hardcoded por conta própria.

---

## Verificação

- Rodar um grep por `D4AF37` e por `Mazza` em `app/views/` após as edições — não deve sobrar
  nenhuma ocorrência.
- Disparar pelo menos dois emails diferentes (ex.: convite de agente via Devise e uma
  notificação via mailer Liquid) e conferir visualmente a cor do botão/accent-bar/links e o
  nome da marca no rodapé.
