# Task: Adaptar `AddItemModal.vue` — pré-preenchimento de contato/conversa + "Atribuir a mim"

## Objetivo

Adaptar o modal de criação de oportunidade (hoje usado só pelo board do Kanban) para funcionar
também a partir da sidebar da conversa (task 07) e da aba de oportunidades do contato (task 08):

1. Aceitar contato/conversa pré-preenchidos, pulando a busca manual.
2. Aceitar seleção de pipeline (o board não precisa disso — já está dentro de um pipeline ativo;
   conversa/contato precisam, já que a oportunidade pode ir pra qualquer pipeline do agente).
3. Novo checkbox **"Atribuir a mim"**, disponível em **todos** os lugares que criam uma oportunidade
   (inclusive o board, já que todos usam este mesmo componente) — se marcado, a oportunidade nasce
   atribuída a quem está criando; se desmarcado, comportamento atual (cai na atribuição automática
   do pipeline, se ativada, ou fica sem responsável).

## Diagnóstico (código atual verificado)

`app/javascript/dashboard/routes/dashboard/kanban/components/AddItemModal.vue` (arquivo completo já
lido): só aceita prop `stageId`, sempre usa `activePipeline`/`getStagesForPipeline` da store
`kanban`, obriga busca manual de contato (`ContactAPI.search`), e o payload de `handleSubmit` nunca
inclui `assignee_id`:

```javascript
const props = defineProps({
  stageId: { type: Number, default: null },
});

const form = reactive({
  title: '',
  value: '',
  pipeline_stage_id: props.stageId || stages.value[0]?.id || null,
});

const handleSubmit = async () => {
  if (!selectedContact.value) return;
  try {
    const item = await store.dispatch('kanban/createItem', {
      contact_id: selectedContact.value.id,
      pipeline_stage_id: form.pipeline_stage_id || stages.value[0]?.id,
      title: form.title || null,
      value: form.value || null,
    });
    ...
```

`kanban/getPipelines` já retorna só os pipelines que o agente participa — filtrado no backend via
`PipelinePolicy::Scope#resolve` → `user.assigned_pipelines` (`app/models/user.rb:142-144`). Não
precisa de endpoint novo pra listar "meus pipelines".

`app/controllers/api/v1/accounts/pipeline_items_controller.rb#create` já dispara
`Pipelines::AutoAssignmentService.new(pipeline_item: @item).perform` depois de criar o item — e esse
serviço já tem a guarda:

```ruby
def perform
  return if pipeline_item.assignee_id.present?
  return unless pipeline.enable_auto_assignment?
  ...
```

Ou seja: **se o payload de criação já mandar `assignee_id`, o serviço de atribuição automática
recua sozinho** — o checkbox "Atribuir a mim" não precisa de nenhuma mudança de backend, só o
frontend passar a enviar o campo (que `item_params` já permite,
`app/controllers/api/v1/accounts/pipeline_items_controller.rb:65-70` — `:assignee_id` já está na
lista).

`app/javascript/dashboard/routes/dashboard/kanban/pages/KanbanIndex.vue` invoca o modal hoje só com
`stage-id`:

```vue
<AddItemModal
  v-if="showAddItemModal"
  :stage-id="selectedStageId"
  @close="showAddItemModal = false"
  @created="showAddItemModal = false"
/>
```

---

## 1. `AddItemModal.vue`

### Novas props

```javascript
const props = defineProps({
  stageId: { type: Number, default: null },
  contactId: { type: Number, default: null },
  conversationId: { type: Number, default: null },
  pipelineId: { type: Number, default: null },
});
```

### Contato pré-preenchido

Quando `props.contactId` vier preenchido: esconder o campo de busca manual, buscar os dados do
contato via `store.getters['contacts/getContactById'](props.contactId)` (despachar
`store.dispatch('contacts/show', { id: props.contactId })` no mount se ainda não estiver na store) e
mostrar como somente leitura (mesmo estilo do bloco de contato read-only já usado em
`KanbanCardDetail.vue`, linhas 151-174 — avatar, nome, email).

```javascript
const preselectedContact = useMapGetter('contacts/getContactById');
const contactForDisplay = computed(() =>
  props.contactId ? preselectedContact.value(props.contactId) : selectedContact.value
);

onMounted(() => {
  if (props.contactId && !contactForDisplay.value) {
    store.dispatch('contacts/show', { id: props.contactId });
  }
});
```

### Seletor de pipeline (só quando `pipelineId` não vier via prop)

```javascript
const pipelines = useMapGetter('kanban/getPipelines');
const selectedPipelineId = ref(props.pipelineId || null);

const stages = computed(() => {
  const pipelineId = props.pipelineId || selectedPipelineId.value || activePipeline.value?.id;
  return pipelineId ? getStagesForPipeline.value(pipelineId) : [];
});

onMounted(async () => {
  if (!props.pipelineId && !activePipeline.value) {
    await store.dispatch('kanban/fetchPipelines');
  }
});
```

No template, mostrar o `<select v-model="selectedPipelineId">` (alimentado por `pipelines.value`)
**só quando `!props.pipelineId && !activePipeline.value`** (ou seja: quando o modal é aberto fora do
contexto do board, sem um pipeline ativo já definido) — no board, o comportamento atual (usa
`activePipeline`) permanece inalterado.

### Etapa inicial = `stage_type: 'start'`

```javascript
watch(stages, newStages => {
  if (!form.pipeline_stage_id && newStages.length) {
    const startStage = newStages.find(s => s.stage_type === 'start');
    form.pipeline_stage_id = props.stageId || startStage?.id || newStages[0]?.id;
  }
});
```

(usa o conceito de etapa obrigatória inicial já implementado na task 03 — `PipelineStage.stage_type`.)

### Checkbox "Atribuir a mim"

```javascript
const currentUser = useMapGetter('getCurrentUser');
const assignToMe = ref(false);
```

```vue
<div class="flex items-center gap-2">
  <input id="assign-to-me" v-model="assignToMe" type="checkbox" />
  <label for="assign-to-me" class="text-sm text-slate-600 dark:text-slate-400">
    {{ t('KANBAN.ITEM.ASSIGN_TO_ME') }}
  </label>
</div>
```

Posicionar logo abaixo do seletor de "Etapa" no template (linha ~150 do arquivo atual).

### `handleSubmit`

```javascript
const handleSubmit = async () => {
  const contactIdToUse = props.contactId || selectedContact.value?.id;
  if (!contactIdToUse) return;
  try {
    const item = await store.dispatch('kanban/createItem', {
      contact_id: contactIdToUse,
      conversation_id: props.conversationId || null,
      pipeline_stage_id: form.pipeline_stage_id,
      title: form.title || null,
      value: form.value || null,
      assignee_id: assignToMe.value ? currentUser.value.id : null,
    });
    useAlert(t('KANBAN.ITEM.API.CREATE_SUCCESS'));
    emit('created', item);
    emit('close');
  } catch {
    useAlert(t('KANBAN.ITEM.API.ERROR'));
  }
};
```

### Botão "Adicionar" desabilitado

Atualizar a condição `:disabled="!selectedContact || uiFlags.isCreating"` (linha 188) para também
considerar o contato pré-preenchido:

```vue
:disabled="!(props.contactId || selectedContact) || uiFlags.isCreating"
```

## 2. i18n

`app/javascript/dashboard/i18n/locale/en/kanban.json`:
```json
"ITEM": {
  "ASSIGN_TO_ME": "Assign to me"
}
```

`pt_BR/kanban.json`:
```json
"ITEM": {
  "ASSIGN_TO_ME": "Atribuir a mim"
}
```

## 3. Nenhuma mudança em `KanbanIndex.vue`

O uso existente do modal a partir do board continua chamando só com `:stage-id="selectedStageId"` —
sem `contact-id`/`conversation-id`/`pipeline-id`, o modal se comporta exatamente como hoje (busca
manual de contato, usa `activePipeline`), só ganhando o checkbox novo "Atribuir a mim".

---

## Verificação

1. Abrir "Adicionar card" a partir do board do Kanban (fluxo atual) — continua funcionando
   idêntico, com busca manual de contato, etapa pré-selecionada pela coluna clicada, e o novo
   checkbox "Atribuir a mim" disponível.
2. Marcar "Atribuir a mim" e criar — a oportunidade nasce já atribuída ao agente que criou,
   independente de o pipeline ter atribuição automática ativada ou não.
3. Deixar desmarcado e criar, com atribuição automática ativada no pipeline (task 05) — a
   oportunidade cai no round robin normalmente (comportamento inalterado).
4. Deixar desmarcado e criar, sem atribuição automática ativada — a oportunidade fica sem
   responsável (comportamento inalterado).
5. Abrir o modal a partir da sidebar da conversa (task 07) — contato e conversa já vêm
   pré-selecionados (sem campo de busca visível), seletor de pipeline aparece (limitado aos
   pipelines do agente), etapa inicial já vem selecionada por padrão.
6. Abrir o modal a partir da aba de oportunidades do contato (task 08) — mesmo comportamento do
   item 5, mas sem `conversation_id` no payload de criação.
