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
