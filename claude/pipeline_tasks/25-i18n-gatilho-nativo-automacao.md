# Task 25 — i18n: `automation.json` (en + pt_BR) para o gatilho nativo de pipeline

Parte do Grupo E ([visão geral](00-visao-geral.md)). Depende da task 24 (chaves usadas pelos
componentes lá adicionados).

## Objetivo

Traduzir os textos novos introduzidos pela task 24. `automation.json` está na lista de exceção
do projeto que mantém `pt_BR` sincronizado manualmente (CLAUDE.md seção 3, confirmado também em
`00-visao-geral.md` linha 70-72) — **as duas chaves vão nos dois arquivos**, não só em `en`.

Arquivos:
`app/javascript/dashboard/i18n/locale/en/automation.json`
`app/javascript/dashboard/i18n/locale/pt_BR/automation.json`

## 1. Bloco `EVENTS`

Hoje (linha 152-158 do `en/automation.json`) só tem as 5 chaves de conversa. Adicionar:
```json
"PIPELINE_ITEM_CREATED": "Pipeline card created",
"PIPELINE_ITEM_STAGE_CHANGED": "Pipeline card stage changed"
```
(pt_BR equivalente: `"Card de pipeline criado"` / `"Estágio do card de pipeline alterado"`.)

## 2. Bloco `ATTRIBUTES`

Hoje (linha 199-217) não tem `STAGE_ID`, `PIPELINE_ID`, `VALUE`. Adicionar:
```json
"PIPELINE_ID": "Pipeline",
"STAGE_ID": "Stage",
"VALUE": "Value"
```
(pt_BR: `"Pipeline"` / `"Estágio"` / `"Valor"`.) Conferir se `ASSIGNEE_NAME`/`TEAM_NAME`/`LABELS`
já existem no bloco (devem existir, reaproveitados de outros eventos) — não duplicar.

## 3. Bloco `ACTIONS`

`SEND_WEBHOOK_EVENT` já deve existir (ação de conversa já usa esse texto) — conferir e
reaproveitar a mesma chave, não criar uma nova. As 7 ações de pipeline (`MOVE_PIPELINE_ITEM_STAGE`
etc., linhas 179-186) já existem desde a task 05 — nada novo aqui.

## Critério de pronto

- `en/automation.json` e `pt_BR/automation.json` com as chaves novas, sem quebrar o JSON
  (validar com `pnpm eslint` ou parse manual).
- Tela de automação, ao selecionar os 2 eventos novos, exibe texto traduzido (não a chave crua)
  em ambos os idiomas.
