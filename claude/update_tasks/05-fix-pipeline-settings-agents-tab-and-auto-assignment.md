# Task: Aba "Agentes" das Configurações de Pipeline — corrigir dropdown + atribuição automática

## Objetivo

A aba "Agentes" de Configurações > Pipelines está aparentemente vazia (só mostra o texto de
descrição e o botão "Atualizar agentes", sem lista/dropdown de agentes visível). Precisa:

1. Corrigir o bug real que impede o dropdown de agentes de aparecer.
2. Adicionar as mesmas opções de atribuição automática que já existem em Caixas de Entrada >
   Agentes: toggle para ativar atribuição automática de oportunidades criadas, e campo de
   quantidade máxima de oportunidades por agente (0 = infinito).

**Pré-requisito**: task `03-feat-pipeline-mandatory-stages-start-won-lost.md` implementada (usa o
`stage_type` para saber quais oportunidades contam como "abertas" na hora de decidir a quem
atribuir).

## Diagnóstico (bug real encontrado, não é um stub)

`app/javascript/dashboard/routes/dashboard/settings/pipelines/PipelineMembersSection.vue` **já tem
toda a lógica implementada** — busca agentes (`agents/get`), busca membros atuais
(`pipelineMembers/get`), monta `agentMenuItems`, tem handlers de add/remove e botão de salvar. O
backend (`PipelineMember` model, `pipeline_members_controller.rb`, rotas) também já existe e
funciona — confirmado por leitura direta.

**O bug está no uso do `TagInput`** (linhas 79-84 do arquivo):

```vue
<TagInput
  :model-value="selectedAgentNames"
  :menu-items="agentMenuItems"
  @add="handleAgentAdd"
  @remove="handleAgentRemove"
/>
```

Comparado com o uso equivalente em `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/CollaboratorsPage.vue:373-397`:

```vue
<TagInput
  :model-value="selectedAgentNames"
  :placeholder="$t('INBOX_MGMT.ADD.AGENTS.PICK_AGENTS')"
  :menu-items="agentMenuItems"
  show-dropdown
  skip-label-dedup
  :auto-open-dropdown="false"
  @add="handleAgentAdd"
  @remove="handleAgentRemove"
/>
```

Em `app/javascript/dashboard/components-next/taginput/TagInput.vue:79-83`:

```javascript
const showDropdownMenu = computed(() =>
  props.mode === MODE.SINGLE && tags.value.length >= 1
    ? false
    : props.showDropdown && isFocused.value
);
```

Como `showDropdown` tem `default: false` e `PipelineMembersSection.vue` nunca passa
`show-dropdown`, `showDropdownMenu` é **sempre `false`** — a lista de agentes nunca abre ao
clicar/focar. Esse é o bug exato de "não mostra nada".

O `Pipeline` model não tem nenhum campo de atribuição automática hoje (`enable_auto_assignment`,
limite por agente não existem na tabela `pipelines`).

O sistema de round-robin já existente (`app/services/auto_assignment/round_robin_selector.rb`,
`agent_assignment_service.rb`, `inbox_round_robin_service.rb`) é acoplado a **conversas** e usa
Redis + status online do agente (`OnlineStatusTracker`) — desenhado para fila de atendimento ao
vivo. Replicar esse sistema 1:1 para oportunidades seria escopo desnecessário: o pedido aqui é uma
regra simples (limite configurável por agente, 0 = infinito, toggle liga/desliga), sem
dependência de status online. A solução é um serviço próprio, mais simples, específico de
`PipelineItem`.

---

## 1. Corrigir o bug do dropdown (fazer isso primeiro, é independente do resto)

### `PipelineMembersSection.vue`

```vue
<TagInput
  :model-value="selectedAgentNames"
  :placeholder="t('PIPELINE_MGMT.AGENTS.SEARCH_PLACEHOLDER')"
  :menu-items="agentMenuItems"
  show-dropdown
  skip-label-dedup
  :auto-open-dropdown="false"
  @add="handleAgentAdd"
  @remove="handleAgentRemove"
/>
```

Adicionar a chave `PIPELINE_MGMT.AGENTS.SEARCH_PLACEHOLDER` em `pipelineMgmt.json` (en: "Search
agents...", pt_BR: "Buscar agentes...").

---

## 2. Backend — campos de atribuição automática

### 2.1 Migration

```bash
bundle exec rails g migration AddAutoAssignmentToPipelines enable_auto_assignment:boolean max_assignment_limit:integer
```

```ruby
class AddAutoAssignmentToPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :pipelines, :enable_auto_assignment, :boolean, null: false, default: false
    add_column :pipelines, :max_assignment_limit, :integer, null: false, default: 0
  end
end
```

### 2.2 `app/models/pipeline.rb`

```ruby
validates :max_assignment_limit, numericality: { greater_than_or_equal_to: 0 }
```

### 2.3 `app/controllers/api/v1/accounts/pipelines_controller.rb`

No método de params usado pelo `update` (localizar o nome exato — provavelmente
`pipeline_params`), adicionar `:enable_auto_assignment` e `:max_assignment_limit` à lista
`permit(...)`.

### 2.4 Serviço de atribuição automática — `app/services/pipelines/auto_assignment_service.rb`

```ruby
class Pipelines::AutoAssignmentService
  pattr_initialize [:pipeline_item!]

  def perform
    return if pipeline_item.assignee_id.present?
    return unless pipeline.enable_auto_assignment?

    agent = next_eligible_agent
    pipeline_item.update(assignee_id: agent.id) if agent
  end

  private

  def pipeline
    @pipeline ||= pipeline_item.pipeline_stage.pipeline
  end

  def next_eligible_agent
    members = pipeline.members.order(:id)
    return nil if members.empty?

    counts = open_items_count_by_agent
    eligible = members.reject do |member|
      pipeline.max_assignment_limit.positive? && counts[member.id].to_i >= pipeline.max_assignment_limit
    end

    eligible.min_by { |member| counts[member.id].to_i }
  end

  def open_items_count_by_agent
    PipelineItem
      .joins(:pipeline_stage)
      .where(pipeline_stage: { pipeline_id: pipeline.id })
      .where.not(pipeline_stage: { stage_type: PipelineStage.stage_types.values_at('won', 'lost') })
      .where.not(assignee_id: nil)
      .group(:assignee_id)
      .count
  end
end
```

(`pipeline.members.order(:id)` como critério de desempate por "membro mais antigo" — se
`pipeline_members` tiver `created_at`, preferir `pipeline.pipeline_members.order(:created_at).map(&:user)`
para refletir exatamente ordem de entrada no pipeline; confirmar durante a implementação qual fica
mais correto dado o schema real de `pipeline_members`.)

### 2.5 Hook — `app/controllers/api/v1/accounts/pipeline_items_controller.rb#create`

Depois de criar o `pipeline_item` com sucesso, se `assignee_id` não veio no payload:

```ruby
Pipelines::AutoAssignmentService.new(pipeline_item: @pipeline_item).perform
```

(confirmar o nome exato da variável de instância usada no `create` atual antes de aplicar o diff.)

---

## 3. Frontend — seção de atribuição automática

### 3.1 `PipelineMembersSection.vue`

Adicionar estado e handlers:

```javascript
const pipeline = computed(() => getters['kanban/getPipelines'].value.find(p => p.id === props.pipelineId));
const enableAutoAssignment = ref(false);
const maxAssignmentLimit = ref(0);

watch(pipeline, p => {
  if (p) {
    enableAutoAssignment.value = p.enable_auto_assignment ?? false;
    maxAssignmentLimit.value = p.max_assignment_limit ?? 0;
  }
}, { immediate: true });

const handleToggleAutoAssignment = async value => {
  enableAutoAssignment.value = value;
  await store.dispatch('kanban/updatePipeline', {
    id: props.pipelineId,
    enable_auto_assignment: value,
  });
};

const handleUpdateMaxAssignmentLimit = async () => {
  await store.dispatch('kanban/updatePipeline', {
    id: props.pipelineId,
    max_assignment_limit: Number(maxAssignmentLimit.value) || 0,
  });
};
```

**Confirmar antes de implementar** a assinatura atual de `kanban/updatePipeline` em
`app/javascript/dashboard/store/modules/kanban/actions.js` — se ela já aceita um payload parcial
(`{ id, ...changes }`) ou precisa de ajuste para aceitar os dois campos novos.

No template, adicionar entre a descrição e o `TagInput`:

```vue
<SettingsToggleSection
  v-model="enableAutoAssignment"
  :header="t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.TITLE')"
  :description="t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.DESCRIPTION')"
  @update:model-value="handleToggleAutoAssignment"
>
  <woot-input
    v-model="maxAssignmentLimit"
    type="number"
    min="0"
    :label="t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.MAX_LIMIT_LABEL')"
    :help-text="t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.MAX_LIMIT_HELP')"
    @blur="handleUpdateMaxAssignmentLimit"
  />
</SettingsToggleSection>
```

Importar `SettingsToggleSection` de `dashboard/components-next/Settings/SettingsToggleSection.vue`
(mesmo componente usado por `CollaboratorsPage.vue`) — **confirmar o slot/API exata do componente**
lendo o arquivo antes de implementar (o snippet acima assume um slot default para conteúdo extra
dentro da seção, igual usado por `CollaboratorsPage.vue`; ajustar se a API real for diferente).

### 3.2 i18n

`pipelineMgmt.json` (en):
```json
"AGENTS": {
  "SEARCH_PLACEHOLDER": "Search agents...",
  "AUTO_ASSIGNMENT": {
    "TITLE": "Automatic assignment",
    "DESCRIPTION": "Automatically assign new opportunities to pipeline agents",
    "MAX_LIMIT_LABEL": "Maximum opportunities per agent",
    "MAX_LIMIT_HELP": "0 means unlimited"
  }
}
```

`pipelineMgmt.json` (pt_BR):
```json
"AGENTS": {
  "SEARCH_PLACEHOLDER": "Buscar agentes...",
  "AUTO_ASSIGNMENT": {
    "TITLE": "Atribuição automática",
    "DESCRIPTION": "Atribuir automaticamente novas oportunidades aos agentes do pipeline",
    "MAX_LIMIT_LABEL": "Quantidade máxima de oportunidades por agente",
    "MAX_LIMIT_HELP": "0 significa ilimitado"
  }
}
```

---

## Verificação

1. Abrir Configurações > Pipeline > Agentes — clicar no campo de busca deve abrir o dropdown com a
   lista de agentes disponíveis (bug corrigido).
2. Adicionar 2+ agentes, clicar "Atualizar agentes" — confirmar persistência (recarregar a página e
   ver os agentes continuam lá).
3. Ativar o toggle de atribuição automática, definir limite máximo = 1.
4. Criar uma nova oportunidade sem especificar responsável — deve ser atribuída automaticamente a
   um dos agentes do pipeline.
5. Criar uma segunda oportunidade — deve ir para o outro agente (round robin por menor contagem),
   já que o primeiro atingiu o limite de 1.
6. Criar uma terceira oportunidade — nenhum agente elegível (ambos no limite) — deve ficar sem
   responsável (sem erro).
7. Mudar o limite para 0 (ilimitado) — novas oportunidades voltam a ser distribuídas livremente
   entre os agentes, sem bloqueio por contagem.
8. Mover uma oportunidade para a etapa "Ganho" ou "Perdido" (task 03) — confirmar que ela deixa de
   contar na distribuição de carga do agente (ex.: um agente no limite fica elegível de novo depois
   que uma de suas oportunidades é movida para "Ganho").
9. Desativar o toggle — novas oportunidades deixam de ser atribuídas automaticamente.
