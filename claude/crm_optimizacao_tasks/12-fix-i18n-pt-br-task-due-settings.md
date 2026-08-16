# Task 12 — Fix: i18n `pt_BR` incompleto para `task_due` em `settings.json`

Severidade: 🟢 Baixa. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`app/javascript/dashboard/i18n/locale/en/settings.json:164` tem:

```json
"TASK_DUE": "A task is due"
```

dentro de `PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES`. O arquivo irmão
`app/javascript/dashboard/i18n/locale/pt_BR/settings.json` **não tem** essa chave
(confirmado — busca por `task_due`/`TASK_DUE` no arquivo não encontra nenhuma ocorrência).

O commit `5b903ade2` ("fix(notifications): render task_due notifications instead of
crashing the list") sincronizou `pt_BR/generalSettings.json` (`TYPE_LABEL.task_due`), mas
não tocou o arquivo irmão `pt_BR/settings.json` — deixando a tela de preferências de
notificação do perfil (`PROFILE_SETTINGS.FORM.NOTIFICATIONS`) sem tradução para esse item em
pt_BR (provavelmente cai no fallback `en` ou mostra a chave crua, dependendo de como
`vue-i18n` está configurado no projeto).

## Nota sobre a regra de i18n deste projeto

A regra geral do `AGENTS.md` é só editar `en.yml`/`en.json`; a exceção documentada é só o
domínio kanban/automation/macros. `settings.json` não está nessa exceção — mas como o commit
anterior já começou a sincronizar `pt_BR` para esse mesmo recurso (`task_due`) em
`generalSettings.json`, faz sentido completar a mesma sincronização aqui, para não deixar a
tela com tradução pela metade (um arquivo sincronizado, outro não).

## O que corrigir

Adicionar em `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`, dentro de
`PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES` (mesmo nível/formato das outras chaves
irmãs já existentes nesse bloco):

```json
"TASK_DUE": "Uma tarefa está vencendo"
```

(ajustar o texto exato para o tom já usado nas outras traduções pt_BR do mesmo bloco, se
houver um padrão de fraseado a seguir — conferir as chaves vizinhas antes de finalizar o
texto).

## Testes

Testar manualmente: trocar o idioma do dashboard para pt_BR, abrir Perfil → Preferências de
Notificação, confirmar que a linha de "task_due" mostra o texto traduzido em vez de cair no
fallback em inglês ou mostrar a chave crua.

## Critério de pronto

- Chave `TASK_DUE` presente em `pt_BR/settings.json` no mesmo caminho que em `en/settings.json`.
- Tela de preferências de notificação em pt_BR exibe o texto traduzido.
