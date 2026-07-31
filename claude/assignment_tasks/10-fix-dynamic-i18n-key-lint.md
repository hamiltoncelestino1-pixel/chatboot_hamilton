# Task: Remover chave i18n dinâmica em `assignmentModeOptions` (quebra de lint)

## Objetivo

`CollaboratorsPage.vue` usa uma chave de tradução construída dinamicamente
(interpolação de string), o que dispara o lint `@intlify/vue-i18n/no-dynamic-keys` —
contradizendo o próprio critério de aceite da task `04` ("`pnpm eslint` limpo").

---

## Contexto importante

`app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/CollaboratorsPage.vue:129-138`:
```js
const assignmentModeOptions = computed(() =>
  OPTIONS.ORDER.map(key => ({
    key,
    label: t(`INBOX_MGMT.ASSIGNMENT.MODE.${key.toUpperCase()}.LABEL`),
    description: t(
      `INBOX_MGMT.ASSIGNMENT.MODE.${key.toUpperCase()}.DESCRIPTION`
    ),
    isActive: assignmentMode.value === key,
  }))
);
```

Rodar `npx eslint` neste arquivo produz:
```
132:12  warning  '`INBOX_MGMT.ASSIGNMENT.MODE.${key.toUpperCase()}.LABEL`' dynamic key is used  @intlify/vue-i18n/no-dynamic-keys
133:18  warning  '`INBOX_MGMT.ASSIGNMENT.MODE.${key.toUpperCase()}.DESCRIPTION`' dynamic key is used  @intlify/vue-i18n/no-dynamic-keys
```

O mesmo arquivo já resolve exatamente esse tipo de problema (mapear um valor de enum
para um label traduzido) sem chave dinâmica, em dois computeds vizinhos:

```js
const assignmentOrderLabel = computed(() => {
  if (!assignmentPolicy.value) return '';
  const priority = assignmentPolicy.value.conversation_priority;
  if (priority === 'earliest_created') {
    return t('INBOX_MGMT.ASSIGNMENT.PRIORITY.EARLIEST_CREATED');
  }
  if (priority === 'longest_waiting') {
    return t('INBOX_MGMT.ASSIGNMENT.PRIORITY.LONGEST_WAITING');
  }
  return priority;
});

const assignmentMethodLabel = computed(() => {
  if (!assignmentPolicy.value) return '';
  const order = assignmentPolicy.value.assignment_order;
  if (order === 'round_robin') {
    return t('INBOX_MGMT.ASSIGNMENT.METHOD.ROUND_ROBIN');
  }
  if (order === 'balanced') {
    return t('INBOX_MGMT.ASSIGNMENT.METHOD.BALANCED');
  }
  return order;
});
```

Uma busca no dashboard inteiro não encontra nenhum `// eslint-disable` para
`no-dynamic-keys` — não existe precedente de suprimir essa regra no projeto, então a
correção é reescrever, não silenciar o lint.

`OPTIONS.ORDER` vem de
`app/javascript/dashboard/routes/dashboard/settings/assignmentPolicy/constants.js`
(`[ROUND_ROBIN, BALANCED]`, ou seja só 2 valores possíveis — `'round_robin'` e
`'balanced'`).

---

## O que precisa ser feito

Reescrever `assignmentModeOptions` para usar chaves de tradução literais (estáticas),
no mesmo espírito de `assignmentOrderLabel`/`assignmentMethodLabel` — por exemplo, um
`if`/`else` (ou objeto de lookup com chaves de string literais, não interpoladas) que
mapeia `ROUND_ROBIN`/`BALANCED` para as chaves `t('INBOX_MGMT.ASSIGNMENT.MODE.ROUND_ROBIN.LABEL')`
/ `t('INBOX_MGMT.ASSIGNMENT.MODE.BALANCED.LABEL')` (e equivalente para `.DESCRIPTION`)
escritas por extenso no código-fonte.

Manter o resultado (`{ key, label, description, isActive }` por opção, na mesma ordem
de `OPTIONS.ORDER`) idêntico ao atual — é só a forma de obter `label`/`description` que
muda, não o formato do array nem o comportamento visual.

---

## Verificação

- `npx eslint app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/CollaboratorsPage.vue`
  sem nenhum warning de `@intlify/vue-i18n/no-dynamic-keys`.
- `pnpm eslint` (ou o comando de lint completo do projeto) limpo.
- Manual (`pnpm dev`): abrir Settings → Inbox → Collaborators numa inbox sem policy
  vinculada e confirmar visualmente que os dois `RadioCard` (Rodízio/Por demanda) ainda
  mostram label e descrição corretos — sem regressão visual.
- Testes existentes de `CollaboratorsPage.spec.js` que dependem de
  `assignmentModeOptions` (se houver) continuam passando.
