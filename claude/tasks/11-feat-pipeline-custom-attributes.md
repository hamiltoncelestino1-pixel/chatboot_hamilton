# Task: Campos Personalizados (Custom Attributes) para Oportunidades

## Objetivo

Hoje `CustomAttributeDefinition` (`app/models/custom_attribute_definition.rb`) só suporta
`attribute_model: { conversation_attribute: 0, contact_attribute: 1 }`, e a tela de Configurações >
Atributos Personalizados (`settings/attributes/Index.vue`) só mostra 2 abas: Conversas e Contatos.

Esta task adiciona um terceiro `attribute_model` (`pipeline_item_attribute`), uma coluna
`custom_attributes:jsonb` em `PipelineItem` para armazenar os valores, a 3ª aba "Oportunidades" na
tela de atributos, e a exibição/edição desses campos no card de oportunidade do Kanban.

---

## 1. Migração

```ruby
class AddCustomAttributesToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_items, :custom_attributes, :jsonb, default: {}, null: false
  end
end
```

---

## 2. `app/models/custom_attribute_definition.rb`

Arquivo atual (lido integralmente):

```ruby
STANDARD_ATTRIBUTES = {
  :conversation => %w[status priority assignee_id inbox_id team_id display_id campaign_id labels browser_language country_code referer created_at
                      last_activity_at],
  :contact => %w[name email phone_number identifier country_code city company_name created_at last_activity_at referer blocked]
}.freeze
```

Adicionar a chave `:pipeline_item` (nomes de coluna reservados de `PipelineItem`, incluindo os
campos adicionados nas tasks 08/10):

```ruby
STANDARD_ATTRIBUTES = {
  :conversation => %w[status priority assignee_id inbox_id team_id display_id campaign_id labels browser_language country_code referer created_at
                      last_activity_at],
  :contact => %w[name email phone_number identifier country_code city company_name created_at last_activity_at referer blocked],
  :pipeline_item => %w[title value notes position pipeline_stage_id contact_id conversation_id assignee_id team_id labels created_at]
}.freeze
```

Adicionar o valor ao enum:

```ruby
enum attribute_model: { conversation_attribute: 0, contact_attribute: 1, pipeline_item_attribute: 2 }
```

Atualizar `attribute_must_not_conflict` para o terceiro branch:

```ruby
def attribute_must_not_conflict
  model_keys = { 'conversation_attribute' => :conversation, 'contact_attribute' => :contact, 'pipeline_item_attribute' => :pipeline_item }[attribute_model]
  return unless attribute_key.in?(STANDARD_ATTRIBUTES[model_keys])

  errors.add(:attribute_key, I18n.t('errors.custom_attribute_definition.key_conflict'))
end
```

Nenhuma outra mudança necessária neste model — `enum` é aditivo por nome (não por posição), e o
scope `with_attribute_model` já é genérico.

---

## 3. `app/models/pipeline_item.rb`

Nenhuma mudança de validação necessária — a coluna `custom_attributes:jsonb default: {}` já
funciona como em `Conversation`/`Contact` (que expõem `custom_attributes` diretamente, sem
validação de schema forte, deixando a validação de tipo para a definição no frontend).

---

## 4. `app/controllers/api/v1/accounts/pipeline_items_controller.rb`

```ruby
def item_params
  params.require(:pipeline_item).permit(
    :pipeline_stage_id, :contact_id, :conversation_id,
    :title, :value, :notes, :position, :assignee_id, :team_id,
    custom_attributes: {}
  )
end
```

---

## 5. `app/controllers/api/v1/accounts/custom_attribute_definitions_controller.rb`

Nenhuma mudança de lógica — `with_attribute_model` já filtra pelo valor recebido em
`permitted_params[:attribute_model]`, que passa a aceitar `pipeline_item_attribute` automaticamente.

---

## 6. `app/views/api/v1/models/_pipeline_item.json.jbuilder`

Adicionar ao partial (acumulando com as mudanças das tasks 08/10):

```jbuilder
json.custom_attributes resource.custom_attributes
```

---

## 7. Frontend — 3ª aba em Configurações > Atributos Personalizados

### `app/javascript/dashboard/routes/dashboard/settings/attributes/constants.js`

Arquivo atual:

```javascript
export const ATTRIBUTE_MODELS = [
  { id: 0, key: 'CONVERSATION' },
  { id: 1, key: 'CONTACT' },
];
```

Adicionar:

```javascript
export const ATTRIBUTE_MODELS = [
  { id: 0, key: 'CONVERSATION' },
  { id: 1, key: 'CONTACT' },
  { id: 2, key: 'PIPELINE_ITEM' },
];
```

(Os `id`s 0/1/2 são enviados diretamente como `attribute_model` na criação — `AddAttribute.vue`
usa `this.attributeModel` como inteiro, que o Rails `enum` aceita nativamente. Não requer nenhuma
outra mudança em `AddAttribute.vue` além dessa constante, pois o `<select>` já itera sobre
`ATTRIBUTE_MODELS`.)

### `app/javascript/dashboard/routes/dashboard/settings/attributes/Index.vue`

Arquivo atual usa 2 abas fixas e um ternário para mapear `selectedTabIndex` → string do model.
Trocar para 3 abas:

```javascript
const tabs = computed(() => [
  { key: 0, name: t('ATTRIBUTES_MGMT.TABS.CONVERSATION') },
  { key: 1, name: t('ATTRIBUTES_MGMT.TABS.CONTACT') },
  { key: 2, name: t('ATTRIBUTES_MGMT.TABS.PIPELINE_ITEM') },
]);

const attributeModel = computed(() => {
  if (selectedTabIndex.value === 1) return 'contact_attribute';
  if (selectedTabIndex.value === 2) return 'pipeline_item_attribute';
  return 'conversation_attribute';
});
```

O restante do arquivo (`attributes`, `filteredAttributes`, `buildBadges`, `AddAttribute`/
`EditAttribute`/delete modal) já é genérico e funciona sem outra mudança — `buildBadges` só aplica
badges de pre-chat/resolution quando `attribute.attribute_model === 'conversation_attribute'`, o
que já é uma guarda segura para o novo model.

---

## 8. Frontend — exibir/editar campos custom no card de oportunidade

### `KanbanCardDetail.vue`

Buscar as definições de `pipeline_item_attribute` e renderizar campos dinamicamente. O store
`attributes` já é genérico (`getAttributesByModel('pipeline_item_attribute')` funciona sem mudança
de código no módulo). Adicionar ao componente:

```javascript
const store = useStore();
const pipelineItemAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('pipeline_item_attribute')
);

onMounted(() => {
  store.dispatch('attributes/get');
});

const customAttributeValues = ref({});
watch(
  () => props.item,
  item => {
    customAttributeValues.value = { ...(item?.custom_attributes || {}) };
  },
  { immediate: true }
);

const handleCustomAttributeChange = async (key, value) => {
  customAttributeValues.value[key] = value;
  await store.dispatch('kanban/updateItem', {
    id: props.item.id,
    custom_attributes: customAttributeValues.value,
  });
};
```

No template, renderizar um input por definição, seguindo `attribute_display_type` (mesmo enum já
usado por Conversa/Contato: `text/number/currency/percent/link/date/list/checkbox`). Localizar o
componente que já faz essa renderização condicional por tipo em Conversa/Contato (buscar por
`attribute_display_type` em `app/javascript/dashboard/components*`) e reaproveitá-lo passando
`pipelineItemAttributes` + `customAttributeValues` — evita duplicar a lógica de switch por tipo.
Se não houver um componente genérico o suficiente para reaproveitar, implementar um switch simples
inline:

```html
<div v-if="pipelineItemAttributes.length" class="space-y-3">
  <label class="block text-xs font-medium text-slate-600 dark:text-slate-400">
    {{ t('KANBAN.ITEM.CUSTOM_ATTRIBUTES_TITLE') }}
  </label>
  <div v-for="attr in pipelineItemAttributes" :key="attr.id">
    <label class="block text-xs text-slate-500 mb-1">{{ attr.attribute_display_name }}</label>
    <input
      v-if="['text', 'link'].includes(attr.attribute_display_type)"
      :value="customAttributeValues[attr.attribute_key]"
      type="text"
      class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
      @change="handleCustomAttributeChange(attr.attribute_key, $event.target.value)"
    />
    <input
      v-else-if="['number', 'currency', 'percent'].includes(attr.attribute_display_type)"
      :value="customAttributeValues[attr.attribute_key]"
      type="number"
      class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
      @change="handleCustomAttributeChange(attr.attribute_key, $event.target.value)"
    />
    <input
      v-else-if="attr.attribute_display_type === 'date'"
      :value="customAttributeValues[attr.attribute_key]"
      type="date"
      class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
      @change="handleCustomAttributeChange(attr.attribute_key, $event.target.value)"
    />
    <input
      v-else-if="attr.attribute_display_type === 'checkbox'"
      :checked="customAttributeValues[attr.attribute_key]"
      type="checkbox"
      @change="handleCustomAttributeChange(attr.attribute_key, $event.target.checked)"
    />
    <select
      v-else-if="attr.attribute_display_type === 'list'"
      :value="customAttributeValues[attr.attribute_key]"
      class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700"
      @change="handleCustomAttributeChange(attr.attribute_key, $event.target.value)"
    >
      <option v-for="val in attr.attribute_values" :key="val" :value="val">{{ val }}</option>
    </select>
  </div>
</div>
```

---

## i18n

`en/settings.json` (bloco `ATTRIBUTES_MGMT`):
```json
"TABS": {
  "PIPELINE_ITEM": "Opportunities"
},
"ATTRIBUTE_MODELS": {
  "PIPELINE_ITEM": "Opportunity"
}
```

`pt_BR/settings.json`:
```json
"TABS": {
  "PIPELINE_ITEM": "Oportunidades"
},
"ATTRIBUTE_MODELS": {
  "PIPELINE_ITEM": "Oportunidade"
}
```

`en/kanban.json` (`KANBAN.ITEM`): `"CUSTOM_ATTRIBUTES_TITLE": "Custom attributes"`.
`pt_BR/kanban.json`: `"CUSTOM_ATTRIBUTES_TITLE": "Campos personalizados"`.

---

## Verificação

1. Ir em Configurações > Atributos Personalizados — confirmar 3ª aba "Oportunidades".
2. Criar um atributo (ex: "Origem do lead", tipo lista com valores ["Indicação","Site","Anúncio"])
   na aba Oportunidades.
3. Confirmar que ele **não aparece** nas abas Conversas/Contatos e vice-versa.
4. Abrir uma oportunidade no Kanban — o campo aparece no formulário, editável, e persiste após
   salvar/reload.
5. Deletar o atributo em Configurações — some do formulário de oportunidade sem erro.
