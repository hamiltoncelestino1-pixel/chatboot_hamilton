# Task 20 — Fix: i18n `pt_BR` falta `PIPELINE_ITEM_STALE` em `settings.json`

Severidade: 🟢 Baixa. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`),
como continuação do fix 12 da auditoria anterior (2026-08-16).

## Objetivo

`app/javascript/dashboard/i18n/locale/en/settings.json:164-165` tem `TASK_DUE` **e**
`PIPELINE_ITEM_STALE` no mesmo bloco `PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES`.
`app/javascript/dashboard/i18n/locale/pt_BR/settings.json:162-165` só tem `TASK_DUE` (o fix 12
da auditoria anterior foi aplicado corretamente para essa chave) — falta
`PIPELINE_ITEM_STALE`, que é uma feature irmã posterior (alerta de card parado, do mesmo
commit `df0251e58` que introduziu o resto do épico CRM), fora do escopo do fix 12 original mas
com a mesma lacuna se repetindo.

## O que corrigir

Adicionar a tradução de `PIPELINE_ITEM_STALE` em
`app/javascript/dashboard/i18n/locale/pt_BR/settings.json`, no mesmo bloco onde `TASK_DUE` já
está, espelhando a chave equivalente em `en/settings.json`.

Nota: `settings.json` não é um dos domínios de exceção documentados (`kanban.json`,
`automation.json`, `macros.json`) que mantêm `pt_BR` sincronizado por regra geral do projeto
— mas como o fix 12 anterior já tratou esse arquivo especificamente pra `TASK_DUE`, completar a
lacuna irmã aqui mantém a consistência já iniciada, em vez de deixar meio pela metade.

## Testes

Testar manualmente com o locale `pt_BR` ativo: abrir a tela de preferências de notificação do
perfil, confirmar que a entrada de "card parado" aparece traduzida, não como chave i18n crua
ou em inglês.

## Critério de pronto

- `PIPELINE_ITEM_STALE` traduzido em `pt_BR/settings.json`, mesmo caminho de `en/settings.json`.

## Resultado (2026-10-05)

Uma linha em `pt_BR/settings.json`, no bloco
`PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES`, logo após `TASK_DUE`:

```json
"PIPELINE_ITEM_STALE": "Um card do pipeline está parado"
```

Terminologia alinhada ao `pt_BR/kanban.json`, que já usa **"card"** e **"Pipeline"**.

### Paridade verificada por comparação de conjuntos, não a olho

```
en keys: 10 | pt_BR keys: 10
faltando em pt_BR: nenhuma
sobrando em pt_BR: nenhuma
ordem identica? True
```

Acento conferido como UTF-8 válido (`"Um card do pipeline está parado"`, mesmo `á` da
chave vizinha `TASK_DUE`), `prettier --check` limpo, e o arquivo normalizado de CRLF para LF
depois do `Edit` (**8ª ocorrência** do problema nesta base).

### Precisão sobre o sintoma descrito na task

A task diz "não como chave i18n crua ou em inglês". É **em inglês**: o `createI18n` não define
`fallbackLocale` (`i18n/instance.js:8-12`) e o vue-i18n 9 faz o fallback cair no valor de
`locale`, que é `'en'`. O usuário brasileiro via "A pipeline card has been stalled" no meio de
uma lista em português — nunca a chave crua. Isso importa porque torna esse tipo de defeito
bem mais fácil de passar despercebido numa revisão visual.

### Achado maior, registrado como task 23

Ao medir o resto do domínio, apareceu uma lacuna muito além desta chave:
`pt_BR/tasks.json` **não existe** (21 chaves, UI inteira de Tarefas em inglês) e
`pt_BR/pipelineMgmt.json` está sem **30 de 79** (o bloco `PIPELINE_LOST_REASON_MGMT` inteiro).
No backend, `config/locales/pt_BR.yml` está sem 9 chaves do domínio CRM, incluindo o título e o
corpo das notificações de tarefa vencendo e card parado.

Detalhe completo e medido em [task 23](23-fix-i18n-pt-br-dominio-crm.md).
