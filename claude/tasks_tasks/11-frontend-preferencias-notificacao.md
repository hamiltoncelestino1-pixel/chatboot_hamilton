# Task 11 — Frontend: entrada `task_due` nas preferências de notificação

Parte do Grupo C ([visão geral](00-visao-geral.md)). Depende da [03](03-integracao-notification.md)
(precisa que `task_due` já exista em `Notification::NOTIFICATION_TYPES` no backend).

## Objetivo

A tela `NotificationPreferences.vue` já é genérica — renderiza uma matriz "tipo × email/push"
a partir de `NOTIFICATION_TYPES` (`routes/dashboard/settings/profile/constants.js:1-37`). Esta
task só precisa adicionar uma entrada nova nesse array; nenhuma mudança de componente.

## Implementação

`app/javascript/dashboard/routes/dashboard/settings/profile/constants.js` — adicionar ao
array `NOTIFICATION_TYPES` (linha 1-37), depois de `SLA_MISSED_RESOLUTION`:

```js
{
  label: 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.TASK_DUE',
  value: 'task_due',
},
```

`value: 'task_due'` precisa bater exatamente com a chave do enum criado na task 03
(`Notification::NOTIFICATION_TYPES[:task_due]`) — o backend deriva os nomes de flag
(`email_task_due`/`push_task_due`) a partir dessa mesma string, então qualquer divergência de
grafia quebra silenciosamente (a checkbox aparece mas nunca salva).

**Não replicar o filtro de feature `sla`** que a tela já faz para os 3 tipos de SLA
(`NotificationPreferences.vue:43-53`, `if (!account.feature_enabled?('sla')) filtra fora`) — a
feature de Tasks não tem gate de plano/feature flag (é core, ver decisão na visão geral), então
`task_due` deve aparecer pra todo mundo sem condicional.

## i18n

`PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.TASK_DUE` — mesmo arquivo/domínio das outras chaves
de `NOTIFICATION_TYPES` (settings/profile, não é domínio Kanban) — regra geral, só `en`.

## Testes

Não aplicável (mudança de dado estático, sem lógica nova).

## Critério de pronto

- Abrir Configurações → Perfil → Notificações (`pnpm dev`), a linha "Tarefa vencida" (ou label
  equivalente) aparece na matriz com checkboxes de email/push, desmarcadas por padrão (mesmo
  comportamento dos outros 7 tipos — só `conversation_assignment` nasce marcado, ver nota na
  visão geral).
- Marcar o checkbox de email/push, salvar, recarregar a página — estado persiste.
