# Task: Atributos personalizados — menu colapsável no card + checkbox "exibir no card"

## Objetivo

Hoje, no painel "Editar card" do Kanban, os atributos personalizados de oportunidade aparecem como
uma lista plana e sempre visível. Precisamos de duas mudanças:

1. Agrupar os atributos personalizados dentro de um menu colapsável (fechado por padrão) no painel
   de edição do card.
2. Permitir marcar um atributo, na tela de Configurações > Atributos Personalizados, como "exibir
   sempre no card" — esses atributos aparecem diretamente no card da coluna do Kanban, sem precisar
   abrir o painel de edição.

## Diagnóstico (código atual verificado)

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue:213-259` renderiza
os atributos de `pipelineItemAttributes` (getter `attributes/getAttributesByModel('pipeline_item_attribute')`)
como uma lista de `<input>`/`<select>` sempre visível, sem nenhum agrupamento.

`app/models/custom_attribute_definition.rb` não tem nenhum campo de "exibição no card" — a tabela
`custom_attribute_definitions` só tem `attribute_display_name`, `attribute_display_type`,
`attribute_key`, `attribute_model`, `attribute_values`, `default_value`, `regex_pattern`, `regex_cue`.

Existe precedente pronto para o padrão colapsável em
`app/javascript/dashboard/routes/dashboard/conversation/customAttributes/CustomAttributes.vue`, que
usa `AccordionItem` (`app/javascript/dashboard/components/Accordion/AccordionItem.vue` — props
`title`, `isOpen`, `compact`, `icon`, `emoji`; emite `@toggle`).

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCard.vue` hoje só mostra
avatar/nome/email do contato, labels e valor — nenhum atributo personalizado.

---

## 1. Backend

### 1.1 Migration

```bash
bundle exec rails g migration AddDisplayOnCardToCustomAttributeDefinitions display_on_card:boolean
```

```ruby
class AddDisplayOnCardToCustomAttributeDefinitions < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_attribute_definitions, :display_on_card, :boolean, null: false, default: false
  end
end
```

### 1.2 `app/controllers/api/v1/accounts/custom_attribute_definitions_controller.rb`

Localizar `custom_attribute_definition_params` (`permit(...)`) e adicionar `:display_on_card` à
lista de campos permitidos. Nenhuma outra mudança de controller necessária — o campo é opcional e
não afeta `contact_attribute`/`conversation_attribute`.

### 1.3 View JSON

Localizar o jbuilder/serializer que expõe `CustomAttributeDefinition` (provavelmente
`app/views/api/v1/models/_custom_attribute_definition.json.jbuilder` ou serialização inline no
controller `index`/`show`) e adicionar `json.display_on_card resource.display_on_card`.

---

## 2. Frontend — Configurações > Atributos Personalizados

### 2.1 `app/javascript/dashboard/routes/dashboard/settings/attributes/AddAttribute.vue`

No `data()`, adicionar:

```javascript
displayOnCard: false,
```

No template, logo abaixo do `<select v-model="attributeType">` (linha ~227), adicionar:

```vue
<div v-if="attributeModel === 2" class="mb-4">
  <input
    id="display-on-card"
    v-model="displayOnCard"
    type="checkbox"
  />
  <label for="display-on-card" class="inline ml-1">
    {{ $t('ATTRIBUTES_MGMT.ADD.FORM.DISPLAY_ON_CARD.LABEL') }}
  </label>
</div>
```

No `addAttributes()`, incluir `display_on_card: this.displayOnCard` no payload de
`attributes/create`.

### 2.2 Edição de atributo existente

Localizar o componente que edita um `CustomAttributeDefinition` já criado (mesma pasta
`settings/attributes/` — provavelmente um componente de linha/edição inline usado pelo `Index.vue`;
confirmar o nome exato do arquivo antes de implementar). Replicar o mesmo checkbox condicional
(`v-if` no model sendo `pipeline_item_attribute`) e incluir `display_on_card` no payload de
`attributes/update`.

### 2.3 i18n

`app/javascript/dashboard/i18n/locale/en/settings.json` (chave `ATTRIBUTES_MGMT.ADD.FORM`):

```json
"DISPLAY_ON_CARD": {
  "LABEL": "Always show on card"
}
```

`pt_BR/settings.json`:

```json
"DISPLAY_ON_CARD": {
  "LABEL": "Exibir sempre no card"
}
```

---

## 3. Frontend — Kanban

### 3.1 `KanbanCardDetail.vue` — colapsar atributos

Adicionar estado local:

```javascript
const isAttributesOpen = ref(false);
```

Substituir o bloco `<div v-if="pipelineItemAttributes.length" class="space-y-3">` (linha 213) por:

```vue
<AccordionItem
  v-if="pipelineItemAttributes.length"
  :title="t('KANBAN.ITEM.CUSTOM_ATTRIBUTES_TITLE')"
  :is-open="isAttributesOpen"
  compact
  @toggle="isAttributesOpen = !isAttributesOpen"
>
  <div class="space-y-3">
    <!-- v-for existente (linhas 217-258), sem mudanças no conteúdo interno -->
  </div>
</AccordionItem>
```

Importar `AccordionItem` de `dashboard/components/Accordion/AccordionItem.vue`. Remover o antigo
`<p class="text-xs font-medium ...">{{ t('KANBAN.ITEM.CUSTOM_ATTRIBUTES_TITLE') }}</p>` (o título
agora vem do `AccordionItem`).

### 3.2 `KanbanCard.vue` — mostrar atributos marcados `display_on_card`

Adicionar prop/computed novo:

```javascript
const store = useStore(); // se ainda não importado
const pipelineItemAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('pipeline_item_attribute')
);

const visibleAttributes = computed(() =>
  pipelineItemAttributes.value
    .filter(attr => attr.display_on_card)
    .map(attr => ({
      key: attr.attribute_key,
      label: attr.attribute_display_name,
      value: props.item.custom_attributes?.[attr.attribute_key],
    }))
    .filter(attr => attr.value !== undefined && attr.value !== null && attr.value !== '')
);
```

No template, adicionar após o bloco de labels (linha 46-54):

```vue
<div v-if="visibleAttributes.length" class="flex flex-col gap-0.5 mt-1.5">
  <div
    v-for="attr in visibleAttributes"
    :key="attr.key"
    class="text-[10px] text-slate-500 dark:text-slate-400 truncate"
  >
    <span class="font-medium">{{ attr.label }}:</span> {{ attr.value }}
  </div>
</div>
```

**Nota**: `store.dispatch('attributes/get')` já é despachado por `KanbanCardDetail.vue` ao montar;
confirmar que a store de `attributes` já está populada quando o board renderiza os cards pela
primeira vez (pode ser necessário também despachar `attributes/get` em `KanbanIndex.vue` ou
`KanbanBoard.vue` para garantir que `visibleAttributes` funcione mesmo sem abrir nenhum card antes).

---

## Verificação

1. Criar um atributo de oportunidade novo em Configurações > Atributos Personalizados, marcando
   "Exibir sempre no card" — salvar.
2. Abrir um card no Kanban, preencher esse atributo, salvar.
3. Fechar o painel — o valor deve aparecer diretamente no card da coluna.
4. Reabrir o painel — a seção "Atributos personalizados" deve estar fechada por padrão; clicar nela
   deve expandir e mostrar todos os atributos (inclusive os que não têm `display_on_card`).
5. Criar um atributo sem marcar "exibir no card" — confirmar que ele NÃO aparece no card, só dentro
   do painel expandido.
6. Editar um atributo existente e alternar o checkbox — confirmar que a mudança reflete no card.
