# Task: Cobertura de frontend — fiação real do template + cenário `showDirectAssignmentModeUI === false`

## Objetivo

O spec de componente novo `CollaboratorsPage.spec.js` (criado pela task `04`) cobre a
lógica dos handlers isoladamente, mas deixa dois buracos: (1) nunca dispara os eventos a
partir dos componentes filhos de verdade, só chama os métodos do componente diretamente;
(2) nunca testa o cenário em que já existe uma `AssignmentPolicy` vinculada — a própria
razão de existir do novo branch `showDirectAssignmentModeUI` nunca é comprovada em teste.

---

## Contexto importante

`app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/specs/CollaboratorsPage.spec.js`:

**Gap 1** — os testes de handler chamam o método do componente diretamente:
```js
await wrapper.vm.updateAssignmentMode('balanced');
...
await wrapper.vm.updateRestrictToOnlineAgents(true);
```
O componente é montado com `shallowMount`, então `RadioCard` e `SettingsToggleSection`
viram stubs — nenhum teste emite `select`/`update:model-value` a partir desses stubs e
confirma que o handler certo é chamado com o payload certo. Um bug no template (o
`@select="updateAssignmentMode"` sendo removido/renomeado por engano, ou a prop errada
sendo passada ao `RadioCard`) não seria detectado por essa suite.

**Gap 2** — `beforeEach` sempre mocka `assignmentPoliciesAPI.getInboxPolicy` para
rejeitar (`mockRejectedValue`), então `assignmentPolicy.value` é `null` em todo teste do
arquivo. Não existe nenhum teste que resolve `getInboxPolicy` com uma policy de verdade
e confirma que `showDirectAssignmentModeUI` vira `false` (e o card antigo "Default
Policy Linked" volta a aparecer em vez do novo).

---

## O que precisa ser feito

1. Para pelo menos os dois handlers principais (`updateAssignmentMode`,
   `updateRestrictToOnlineAgents`), adicionar (ou converter) testes que disparem o
   evento a partir do componente-stub real
   (`wrapper.findComponent(RadioCard).vm.$emit('select', ...)`, e o equivalente para
   `SettingsToggleSection` via `update:model-value`), confirmando que
   `store.dispatch('inboxes/updateInbox', ...)` é chamado com o payload esperado —
   fechando a lacuna entre "a lógica do handler está certa" e "o template está
   conectado à lógica certa".
2. Adicionar um novo teste (ou `context`) em que `assignmentPoliciesAPI.getInboxPolicy`
   resolve com uma policy válida, e confirmar que `showDirectAssignmentModeUI` é
   `false` — via inspeção do `wrapper` (o card antigo de policy aparece, o novo card de
   `RadioCard`s não aparece).

---

## Verificação

- Suite roda limpa (`pnpm vitest run` ou equivalente do projeto para este arquivo).
- Os novos testes falham se o `@select`/`@update:model-value` for removido do template
  (validação de que a suite de fato protege a fiação), e falham se
  `showDirectAssignmentModeUI` for hardcoded para `true` (validação do Gap 2).
- `pnpm eslint` limpo no arquivo de spec.
