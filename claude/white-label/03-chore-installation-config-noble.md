# Task: Atualizar configuração de instalação para Noble Company

## Objetivo

Trocar os valores de branding em `config/installation_config.yml`, hoje apontando para
"Mazza Advocacia", pelos dados reais da Noble Company. Como o uso é interno (uma marca só),
não é necessário manter suporte a múltiplas marcas — só atualizar os valores.

---

## 1. `config/installation_config.yml` — seção "Branding Related Config" (linhas 16-58)

Estado atual:

```yaml
- name: INSTALLATION_NAME
  value: 'Mazza Advocacia'
- name: LOGO_THUMBNAIL
  value: '/brand-assets/logo_thumbnail.svg'
- name: LOGO
  value: '/brand-assets/logo.svg'
- name: LOGO_DARK
  value: '/brand-assets/logo_dark.svg'
- name: BRAND_URL
  value: 'https://mazzaadvocacia.com.br'
- name: WIDGET_BRAND_URL
  value: 'https://mazzaadvocacia.com.br'
- name: BRAND_NAME
  value: 'Mazza Advocacia'
- name: TERMS_URL
  value: 'https://mazzaadvocacia.com.br/termos-de-uso'
- name: PRIVACY_URL
  value: 'https://mazzaadvocacia.com.br/privacidade'
- name: DISPLAY_MANIFEST
  value: false
```

Trocar para (ajustar URLs para os domínios reais da Noble antes de aplicar):

```yaml
- name: INSTALLATION_NAME
  value: 'Noble Company'
- name: LOGO_THUMBNAIL
  value: '/brand-assets/logo_thumbnail.svg'
- name: LOGO
  value: '/brand-assets/logo.svg'
- name: LOGO_DARK
  value: '/brand-assets/logo_dark.svg'
- name: BRAND_URL
  value: 'https://<dominio-da-noble>'
- name: WIDGET_BRAND_URL
  value: 'https://<dominio-da-noble>'
- name: BRAND_NAME
  value: 'Noble Company'
- name: TERMS_URL
  value: 'https://<dominio-da-noble>/termos-de-uso'
- name: PRIVACY_URL
  value: 'https://<dominio-da-noble>/privacidade'
- name: DISPLAY_MANIFEST
  value: false
```

Os caminhos de `LOGO*` não mudam de nome (os arquivos são substituídos em
`02-chore-replace-brand-assets.md`).

## 2. Verificar tela Super Admin — "Custom Branding"

O grupo de config `custom_branding` é definido em
`enterprise/app/controllers/enterprise/super_admin/app_configs_controller.rb`
(`custom_branding_options`: `LOGO_THUMBNAIL, LOGO, LOGO_DARK, BRAND_NAME, INSTALLATION_NAME,
BRAND_URL, WIDGET_BRAND_URL, TERMS_URL, PRIVACY_URL, DISPLAY_MANIFEST`).

- Não deve exigir mudança de código — é só uma tela que lê os valores do passo 1.
- Depois de aplicar o passo 1 e rodar as migrations/seed necessárias, acessar
  **Super Admin → App Configs → Branding** e confirmar que os novos valores aparecem
  corretamente e são editáveis.

## 3. Checar reconciliação de plano (não deixar resetar o branding)

Se esta instalação algum dia rodar em plano "premium"/enterprise ativado, existe um mecanismo
que reconcilia configs a partir de `enterprise/config/premium_installation_config.yml` (que
tem os defaults originais do Chatwoot, ex. `INSTALLATION_NAME: 'Chatwoot'`), via
`enterprise/app/services/internal/reconcile_plan_config_service.rb`.

- Ler esse service e confirmar se/quando ele sobrescreve chaves de branding já customizadas.
- Se houver risco de reset, documentar isso e decidir (nesta task, só documentar — não
  implementar proteção extra, a menos que o risco seja confirmado como real e imediato).

---

## Verificação

- Reiniciar o Rails (as configs de `installation_config.yml` são carregadas/sincronizadas na
  inicialização — conferir se precisa rodar alguma rake task de sync, ex.
  `rails db:seed` ou o mecanismo específico do projeto para popular `installation_configs`).
- Abrir a tela de login e confirmar o novo nome/URL da marca.
- Abrir **Super Admin → App Configs → Branding** e confirmar os valores.
- Disparar um convite de agente por email e conferir o rodapé "This email was sent by Noble
  Company" com o link correto.
