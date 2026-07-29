# Task: Frontend — toggles de modo de atribuição + online-only em `CollaboratorsPage.vue`

## Objetivo

Expor na aba Collaborators da inbox, sem exigir criar/vincular uma `AssignmentPolicy`:
1. Escolha "Rodízio" vs "Por demanda" (`auto_assignment_config.assignment_mode`).
2. Toggle "Restringir a agentes online" (`auto_assignment_config.restrict_to_online_agents`),
   default desligado (novo comportamento das tasks `05`/`06`: qualquer membro pode receber).

Depende de `01`, `02`, `03` (backend pronto) e `05` (o significado do toggle de online-only só
existe depois que a task `05` implementa o comportamento real).

---

## Contexto importante

`CollaboratorsPage.vue` hoje tem, dentro do slot `#editor` do `SettingsToggleSection`
(`enableAutoAssignment` ligado), **3 estados mutuamente exclusivos** (linhas 409-667, todos
dentro de `v-if="hasAssignmentV2"`):

1. `showAdvancedAssignmentUI && assignmentPolicy` (linha 417) — card da policy vinculada, com
   nome, `assignmentOrderLabel`, `assignmentMethodLabel`, botão "Customize policy".
2. `showAdvancedAssignmentUI && !assignmentPolicy && !isLoadingPolicy` (linha 482) — card
   "Default Policy Linked" com botões "Link existing policy" / "Create new policy".
3. `!showAdvancedAssignmentUI` (linha 583) — card "Default Rules" com regras fixas e, se
   `!hasAdvancedAssignment`, um prompt "Upgrade to Business".

Onde:
```js
const hasAdvancedAssignment = computed(() => isFeatureEnabled('advanced_assignment'));
const hasAssignmentV2 = computed(() => isFeatureEnabled('assignment_v2'));
const showAdvancedAssignmentUI = computed(() => hasAdvancedAssignment.value && hasAssignmentV2.value);
```

**Efeito colateral da task `01`**: como `advanced_assignment` passa a estar sempre habilitada
(e `assignment_v2` já é `enabled: true` por padrão), `showAdvancedAssignmentUI` vira sempre
`true` para toda conta — o branch 3 (`!showAdvancedAssignmentUI`) vira código morto, e o branch
2 (que empurra "Link/Create policy") viraria o padrão para **toda** inbox sem policy — o
oposto do pedido (toggle leve, sem exigir Policy). Por isso é preciso um **4º branch novo**,
inserido **antes** do branch 2, com precedência quando não há policy vinculada.

Padrão de UI já pronto pra reaproveitar (usado hoje no form de Assignment Policy):
`app/javascript/dashboard/components-next/radioCard/RadioCard.vue` (props `label`,
`description`, `is-active`, `disabled`, emite `@select`) +
`app/javascript/dashboard/routes/dashboard/settings/assignmentPolicy/constants.js`:
```js
export const ROUND_ROBIN = 'round_robin';
export const BALANCED = 'balanced';
export const OPTIONS = { ORDER: [ROUND_ROBIN, BALANCED], PRIORITY: [...] };
```

Action/API já usada por `handleToggleAutoAssignment`/`updateInbox` no mesmo arquivo — reaproveitar,
não criar chamada nova:
```js
await store.dispatch('inboxes/updateInbox', { id: props.inbox.id, formData: false, ...payload });
```

`SettingsToggleSection` (`dashboard/components-next/Settings/SettingsToggleSection.vue`) é o
componente já usado para o toggle principal de auto-assignment — reaproveitar em versão
`compact` para o novo toggle de online-only, mesmo padrão visual.

---

## 1. Novo estado e computeds

```diff
 import assignmentPoliciesAPI from 'dashboard/api/assignmentPolicies';
+import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
+import {
+  ROUND_ROBIN,
+  BALANCED,
+  OPTIONS,
+} from 'dashboard/routes/dashboard/settings/assignmentPolicy/constants';
```

```diff
 const enableAutoAssignment = ref(false);
 const maxAssignmentLimit = ref(null);
+const assignmentMode = ref(ROUND_ROBIN);
+const restrictToOnlineAgents = ref(false);
 const assignmentPolicy = ref(null);
 const isLoadingPolicy = ref(false);
```

```diff
 const showAdvancedAssignmentUI = computed(() => {
   return hasAdvancedAssignment.value && hasAssignmentV2.value;
 });
+
+// Estado "sem policy vinculada": mostra o toggle leve round_robin/balanced direto no jsonb da
+// inbox, sem exigir criar/linkar uma AssignmentPolicy completa. Tem precedência sobre o card
+// "Default Policy Linked" existente (inserido antes dele no template).
+const showDirectAssignmentModeUI = computed(
+  () => hasAssignmentV2.value && !assignmentPolicy.value && !isLoadingPolicy.value
+);
+
+const assignmentModeOptions = computed(() =>
+  OPTIONS.ORDER.map(key => ({
+    key,
+    label: t(`INBOX_MGMT.ASSIGNMENT.MODE.${key.toUpperCase()}.LABEL`),
+    description: t(`INBOX_MGMT.ASSIGNMENT.MODE.${key.toUpperCase()}.DESCRIPTION`),
+    isActive: assignmentMode.value === key,
+  }))
+);
```

## 2. Handlers

```diff
+const updateAssignmentMode = async newMode => {
+  const previous = assignmentMode.value;
+  assignmentMode.value = newMode;
+  try {
+    await store.dispatch('inboxes/updateInbox', {
+      id: props.inbox.id,
+      formData: false,
+      auto_assignment_config: {
+        ...props.inbox.auto_assignment_config,
+        assignment_mode: newMode,
+      },
+    });
+    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
+  } catch (error) {
+    assignmentMode.value = previous;
+    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
+  }
+};
+
+const updateRestrictToOnlineAgents = async value => {
+  const previous = restrictToOnlineAgents.value;
+  restrictToOnlineAgents.value = value;
+  try {
+    await store.dispatch('inboxes/updateInbox', {
+      id: props.inbox.id,
+      formData: false,
+      auto_assignment_config: {
+        ...props.inbox.auto_assignment_config,
+        restrict_to_online_agents: value,
+      },
+    });
+    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
+  } catch (error) {
+    restrictToOnlineAgents.value = previous;
+    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
+  }
+};
```

(rollback otimista em caso de erro — mesmo espírito do `moveItem` do módulo `kanban`, evita a UI
ficar mostrando um valor que não foi de fato persistido).

## 3. `setDefaults()`

```diff
 const setDefaults = () => {
   enableAutoAssignment.value = props.inbox.enable_auto_assignment;
   maxAssignmentLimit.value =
     props.inbox.auto_assignment_config?.max_assignment_limit || null;
+  assignmentMode.value =
+    props.inbox.auto_assignment_config?.assignment_mode || ROUND_ROBIN;
+  restrictToOnlineAgents.value = Boolean(
+    props.inbox.auto_assignment_config?.restrict_to_online_agents
+  );
   fetchAttachedAgents();
   if (showAdvancedAssignmentUI.value) {
     fetchAssignmentPolicy();
     fetchAvailablePolicies();
   }
 };
```

## 4. Template — novo branch antes do branch "Default Policy Linked"

Inserir **antes** do bloco `v-else-if="showAdvancedAssignmentUI && !assignmentPolicy && !isLoadingPolicy"`
(linha ~480), como um `v-if`/`v-else-if` a mais na cadeia dentro de `<template v-if="hasAssignmentV2">`:

```vue
<!-- Direct assignment mode toggle - when no policy attached (novo default) -->
<div
  v-if="showDirectAssignmentModeUI"
  class="ltr:pr-0 rtl:pl-0 ltr:pl-4 rtl:pr-4 py-4"
>
  <p class="text-body-main text-n-slate-11 mb-3">
    {{ $t('INBOX_MGMT.ASSIGNMENT.MODE.LABEL') }}
  </p>
  <div class="grid grid-cols-1 xs:grid-cols-2 gap-4 w-full mb-4">
    <RadioCard
      v-for="option in assignmentModeOptions"
      :id="option.key"
      :key="option.key"
      :label="option.label"
      :description="option.description"
      :is-active="option.isActive"
      @select="updateAssignmentMode"
    />
  </div>

  <div class="w-full h-px my-4 bg-n-weak" />

  <NextButton
    :label="$t('INBOX_MGMT.ASSIGNMENT.CREATE_NEW_POLICY')"
    icon="i-lucide-arrow-right"
    trailing-icon
    link
    class="mb-2"
    @click="navigateToCreatePolicy"
  />
</div>

<!-- Default Policy - When no custom policy attached but feature enabled -->
<div
  v-else-if="
    showAdvancedAssignmentUI &&
    !assignmentPolicy &&
    !isLoadingPolicy
  "
>
  ... (bloco existente, sem alteração de conteúdo, só a condição vira v-else-if)
```

Depois do fechamento de `</template>` do `v-if="hasAssignmentV2"` (linha ~637, antes do `<!-- Old UI for non-assignment_v2 -->`),
adicionar o toggle de online-only **fora** da cadeia condicional acima, visível independente do
estado de policy (ele é uma config ortogonal ao modo de atribuição):

```vue
<div class="mt-2">
  <SettingsToggleSection
    v-model="restrictToOnlineAgents"
    compact
    :header="$t('INBOX_MGMT.ASSIGNMENT.RESTRICT_TO_ONLINE_AGENTS.LABEL')"
    :description="$t('INBOX_MGMT.ASSIGNMENT.RESTRICT_TO_ONLINE_AGENTS.DESCRIPTION')"
    @update:model-value="updateRestrictToOnlineAgents"
  />
</div>
```

O branch 3 (`v-else-if="!showAdvancedAssignmentUI"`, "Upgrade to Business") é mantido intacto
como rede de segurança — só renderiza se um Super Admin desligar `advanced_assignment`
pontualmente numa conta específica pós-rollout (cenário raro, mas coerente com o gate mantido em
`assignment_mode_balanced?` na task `03`).

## 5. i18n — `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json`

Dentro de `INBOX_MGMT.ASSIGNMENT` (bloco já existente, ao lado de `PRIORITY`/`METHOD`):
```json
"MODE": {
  "LABEL": "Assignment mode",
  "ROUND_ROBIN": {
    "LABEL": "Round robin",
    "DESCRIPTION": "Distribute conversations evenly, one at a time, in rotation."
  },
  "BALANCED": {
    "LABEL": "Least busy agent",
    "DESCRIPTION": "Assign to the agent with the fewest open conversations in this inbox."
  }
},
"RESTRICT_TO_ONLINE_AGENTS": {
  "LABEL": "Restrict to online agents",
  "DESCRIPTION": "When enabled, only agents currently online can receive automatic assignments. When disabled, any member of this inbox is eligible, online or not."
}
```
Só `en.json` — regra do `AGENTS.md` (este domínio não tem a exceção pt_BR já documentada para
Kanban/Pipeline).

---

## Verificação

- Novo `CollaboratorsPage.spec.js` (verificar se já existe algum spec de componente nessa pasta
  de settings antes de assumir que é o primeiro):
  - `showDirectAssignmentModeUI` é `true` quando `hasAssignmentV2` e sem policy vinculada.
  - Clicar num `RadioCard` dispara `updateAssignmentMode` com a chave correta e
    `store.dispatch('inboxes/updateInbox', ...)` com o payload esperado.
  - Toggle de `restrictToOnlineAgents` dispara `updateRestrictToOnlineAgents`.
  - Rollback: mockar `store.dispatch` rejeitando e confirmar que o `ref` volta ao valor anterior.
- Manual (`pnpm dev`): abrir Settings → Inbox → Collaborators de uma inbox sem policy vinculada,
  confirmar que os dois `RadioCard` aparecem (Rodízio/Por demanda) e que trocar a seleção
  persiste (recarregar a página e conferir que o estado voltou como esperado). Testar o toggle
  de "Restringir a agentes online" da mesma forma. Testar também uma inbox que já tem
  `AssignmentPolicy` vinculada — o card antigo (policy) deve continuar aparecendo sem mudança.
- `pnpm eslint` limpo.
