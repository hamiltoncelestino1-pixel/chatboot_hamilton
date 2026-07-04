# Task: Etiquetas Exclusivas de Pipeline nas Oportunidades

## Objetivo

Hoje `Label` (`app/models/label.rb`) é uma lista única por conta, sem nenhum campo de tipo/
categoria, usada por `Contact` e `Conversation` via o concern `Labelable`
(`app/models/concerns/labelable.rb`, que usa `acts_as_taggable_on :labels` — tagging por
**título/string**, não por FK). `PipelineItem` não inclui esse concern hoje.

Esta task cria um campo `label_type` no `Label` existente (`general_label` vs `pipeline_label`),
faz `PipelineItem` (oportunidade) usar labels — mas **só** as do tipo `pipeline_label` — e separa
a tela de Configurações > Etiquetas em abas.

---

## 1. Migração

```ruby
class AddLabelTypeToLabels < ActiveRecord::Migration[7.1]
  def change
    add_column :labels, :label_type, :integer, default: 0, null: false
    add_index :labels, [:label_type, :account_id]
  end
end
```

Rodar `bundle exec rails db:migrate`.

---

## 2. `app/models/label.rb`

Adicionar o enum e scopes (manter tudo que já existe: `belongs_to :account`, validações,
`default_scope { order(:title) }`):

```ruby
enum label_type: { general_label: 0, pipeline_label: 1 }

scope :general, -> { where(label_type: :general_label) }
scope :for_pipelines, -> { where(label_type: :pipeline_label) }
```

---

## 3. `app/controllers/api/v1/accounts/labels_controller.rb`

Adicionar suporte a filtro por tipo, mantendo retrocompatibilidade (sem o param, retorna tudo):

```ruby
class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_label, except: [:index, :create]
  before_action :check_authorization

  def index
    @labels = policy_scope(Current.account.labels)
    @labels = @labels.where(label_type: params[:label_type]) if params[:label_type].present?
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params)
  end

  def update
    @label.update!(permitted_params)
  end

  def destroy
    @label.destroy!
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  def permitted_params
    params.require(:label).permit(:title, :description, :color, :show_on_sidebar, :label_type)
  end
end
```

O frontend do módulo geral de Labels (`settings/labels/`) deve sempre mandar
`?label_type=general_label`, e o módulo de Configurações > Pipelines (task
`12-feat-pipeline-settings-page.md`) sempre `?label_type=pipeline_label`.

---

## 4. `PipelineItem` ganha labels

### `app/models/pipeline_item.rb`

Adicionar o concern e uma validação que impede usar uma label que não seja do tipo `pipeline_label`
(necessário porque `acts_as_taggable_on` faz o match por título, não por FK — não há como restringir
isso via constraint de banco):

```ruby
class PipelineItem < ApplicationRecord
  include Labelable

  belongs_to :account
  belongs_to :pipeline_stage
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :team, optional: true

  validates :contact_id, presence: true
  validates :pipeline_stage_id, presence: true
  validate :assignee_must_be_pipeline_member
  validate :labels_must_be_pipeline_type

  delegate :pipeline, to: :pipeline_stage

  private

  def labels_must_be_pipeline_type
    return if label_list.blank?

    allowed = account.labels.pipeline_label.pluck(:title)
    invalid = label_list - allowed
    errors.add(:label_list, "invalid pipeline labels: #{invalid.join(', ')}") if invalid.any?
  end

  # ... assignee_must_be_pipeline_member da task 08
end
```

(Combinar com a validação `assignee_must_be_pipeline_member` já adicionada na task
`08-feat-pipeline-agent-assignment-backend.md` — se aquela task ainda não foi aplicada, adicionar
só o bloco de labels.)

---

## 5. Controller dedicado de labels — mirror de `Conversations::LabelsController`

O projeto tem um padrão de subcontrolador dedicado por recurso usando `LabelConcern`
(`app/controllers/concerns/label_concern.rb`):

```ruby
module LabelConcern
  def create
    model.update_labels(permitted_params[:labels])
    @labels = model.label_list
  end

  def index
    @labels = model.label_list
  end
end
```

### Novo `app/controllers/api/v1/accounts/pipeline_items/labels_controller.rb`

```ruby
class Api::V1::Accounts::PipelineItems::LabelsController < Api::V1::Accounts::BaseController
  include LabelConcern
  before_action :fetch_item

  private

  def fetch_item
    @item = Current.account.pipeline_items.find(params[:pipeline_item_id])
  end

  def model
    @model ||= @item
  end

  def permitted_params
    params.permit(:pipeline_item_id, labels: [])
  end
end
```

### Rotas (`config/routes.rb`)

Dentro do bloco `resources :pipeline_items, only: [:create, :show, :update, :destroy]` (top-level,
linha ~278):

```ruby
resources :pipeline_items, only: [:create, :show, :update, :destroy] do
  collection { post :reorder }
  resource :labels, only: [:index, :create], module: :pipeline_items
end
```

### Views

`app/views/api/v1/accounts/pipeline_items/labels/index.json.jbuilder` e `create.json.jbuilder`
(idênticos, mirror de `conversations/labels/*.json.jbuilder`):

```jbuilder
json.payload @labels
```

### `_pipeline_item.json.jbuilder`

Adicionar `json.label_list resource.label_list` ao partial (já alterado nas tasks 08/09 com
assignee/team — acrescentar mais essa linha).

---

## 6. Frontend

### API client novo — `app/javascript/dashboard/api/pipelineItemLabels.js`

Mirror do client de labels de conversa/contato (localizar o arquivo real equivalente, ex.
`dashboard/api/conversationLabels.js`, antes de implementar — mesmo padrão):

```javascript
/* global axios */
import ApiClient from './ApiClient';

class PipelineItemLabels extends ApiClient {
  constructor() {
    super('pipeline_items', { accountScoped: true });
  }

  get(itemId) {
    return axios.get(`${this.url}/${itemId}/labels`);
  }

  update(itemId, labels) {
    return axios.post(`${this.url}/${itemId}/labels`, { labels });
  }
}

export default new PipelineItemLabels();
```

### `app/javascript/dashboard/store/modules/kanban/actions.js`

Adicionar duas actions:

```javascript
fetchItemLabels: async ({ commit }, itemId) => {
  const { data } = await PipelineItemLabelsAPI.get(itemId);
  commit('EDIT_ITEM', { id: itemId, label_list: data.payload });
  return data.payload;
},

updateItemLabels: async ({ commit }, { itemId, labels }) => {
  const { data } = await PipelineItemLabelsAPI.update(itemId, labels);
  commit('EDIT_ITEM', { id: itemId, label_list: data.payload });
  return data.payload;
},
```

(import `PipelineItemLabelsAPI from 'dashboard/api/pipelineItemLabels'` no topo do arquivo.)

### `app/javascript/dashboard/store/modules/labels/getters.js`

Adicionar getters filtrados por tipo (o módulo `labels` já existente busca todas as labels da
conta — os getters apenas filtram o que já está em `state.records`):

```javascript
getGeneralLabels: $state => $state.records.filter(l => l.label_type === 'general_label'),
getPipelineLabels: $state => $state.records.filter(l => l.label_type === 'pipeline_label'),
```

### Componente novo — `PipelineItemLabels.vue`

`app/javascript/dashboard/routes/dashboard/kanban/components/PipelineItemLabels.vue` — mirror
simplificado de `LabelBox.vue` (`routes/dashboard/conversation/labels/LabelBox.vue`, usado por
`ConversationAction.vue`), mas consumindo `labels/getPipelineLabels` em vez da lista geral:

```vue
<script setup>
import { computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  item: { type: Object, required: true },
});

const store = useStore();
const pipelineLabels = useMapGetter('labels/getPipelineLabels');

const activeLabels = computed(() => props.item.label_list || []);

const toggleLabel = async label => {
  const current = activeLabels.value;
  const updated = current.includes(label.title)
    ? current.filter(t => t !== label.title)
    : [...current, label.title];
  await store.dispatch('kanban/updateItemLabels', { itemId: props.item.id, labels: updated });
};
</script>

<template>
  <div class="flex flex-wrap gap-1.5">
    <button
      v-for="label in pipelineLabels"
      :key="label.id"
      class="px-2 py-0.5 rounded-full text-xs font-medium border transition-colors"
      :style="{
        backgroundColor: activeLabels.includes(label.title) ? label.color : 'transparent',
        borderColor: label.color,
        color: activeLabels.includes(label.title) ? '#fff' : label.color,
      }"
      @click="toggleLabel(label)"
    >
      {{ label.title }}
    </button>
  </div>
</template>
```

### `KanbanCardDetail.vue`

Adicionar seção de labels ao formulário (após o seletor de team, antes das notes):

```html
<div>
  <label class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1">
    {{ t('KANBAN.ITEM.LABELS_TITLE') }}
  </label>
  <PipelineItemLabels :item="item" />
</div>
```

### `KanbanCard.vue`

Renderizar chips compactos de label no rodapé do card, junto do avatar do assignee (adicionado na
task 09):

```html
<div v-if="item.label_list?.length" class="flex flex-wrap gap-1 mt-1.5">
  <span
    v-for="label in item.label_list"
    :key="label"
    class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-slate-100 dark:bg-slate-600 text-slate-600 dark:text-slate-200"
  >
    {{ label }}
  </span>
</div>
```

---

## 7. Configurações > Etiquetas ganha abas

### `app/javascript/dashboard/routes/dashboard/settings/labels/Index.vue`

Arquivo atual (lido integralmente) busca `store.dispatch('labels/get')` sem filtro e lista tudo via
getter `labels/getLabels`. Adicionar `TabBar` (mesmo componente e padrão usado em
`settings/attributes/Index.vue`):

```javascript
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const selectedTabIndex = ref(0);
const tabsForTabBar = computed(() => [
  { key: 0, label: t('LABEL_MGMT.TABS.GENERAL') },
  { key: 1, label: t('LABEL_MGMT.TABS.PIPELINE') },
]);
const labelType = computed(() =>
  selectedTabIndex.value ? 'pipeline_label' : 'general_label'
);
const onClickTabChange = tab => {
  selectedTabIndex.value = tab.key;
  searchQuery.value = '';
};
```

Trocar `records` para filtrar pelo getter novo em vez de `labels/getLabels` genérico:

```javascript
const records = computed(() =>
  labelType.value === 'pipeline_label'
    ? getters['labels/getPipelineLabels'].value
    : getters['labels/getGeneralLabels'].value
);
```

No template, adicionar `<template #tabs><TabBar :tabs="tabsForTabBar" :initial-active-tab="selectedTabIndex" @tab-changed="onClickTabChange" /></template>`
dentro do `BaseSettingsHeader` (mesmo slot usado em `attributes/Index.vue`).

`AddLabel.vue`/`EditLabel.vue` precisam passar `label_type: labelType.value` ao criar (via prop
`fixed-label-type` recebida do `Index.vue`, default `'general_label'`).

---

## i18n

`en/kanban.json` (`KANBAN.ITEM`): `"LABELS_TITLE": "Labels"`.
`pt_BR/kanban.json`: `"LABELS_TITLE": "Etiquetas"`.

`en/settings.json` / `pt_BR/settings.json` (bloco `LABEL_MGMT`), adicionar:

```json
"TABS": {
  "GENERAL": "General",
  "PIPELINE": "Pipeline"
}
```
```json
"TABS": {
  "GENERAL": "Gerais",
  "PIPELINE": "Pipeline"
}
```

---

## Nota sobre cascata de exclusão

`Label#destroy` (`labels_controller.rb#destroy`) hoje só remove o registro — como o tagging é por
título/string (gem `acts-as-taggable-on`), oportunidades que usavam a etiqueta simplesmente deixam
de listá-la. Esse já é o comportamento atual para Conversas/Contatos — não é uma regressão, não
precisa de job de limpeza novo.

---

## Verificação

1. Em Configurações > Etiquetas, criar uma etiqueta na aba "Gerais" e outra na aba "Pipeline".
2. Confirmar que a etiqueta "Pipeline" **não aparece** na lista de labels de uma Conversa/Contato.
3. Abrir uma oportunidade no Kanban, aplicar a etiqueta "Pipeline" criada — persiste, aparece como
   chip no card.
4. Tentar aplicar via API uma label do tipo `general_label` a um `PipelineItem` — deve falhar
   (422, `label_list: invalid pipeline labels: ...`).
5. Deletar a etiqueta de pipeline em uso — oportunidade deixa de listá-la, sem erro.
