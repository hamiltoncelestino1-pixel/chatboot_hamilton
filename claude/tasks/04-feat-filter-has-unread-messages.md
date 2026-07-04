# Task: Filtro "Tem mensagens não lidas"

## Problema

Não é possível filtrar conversas pelo estado de leitura do agente. O usuário precisa conseguir filtrar "conversas com mensagens não lidas" e "conversas sem mensagens não lidas".

## Diagnóstico

`has_unread_messages` não é uma coluna real — é um estado derivado de duas colunas existentes:
- `agent_last_seen_at IS NULL OR last_activity_at > agent_last_seen_at` → tem não lidas
- (mesma lógica já implementada na ordenação)

O sistema de filtros suporta SQL customizado via handlers por `data_type` em `filter_helper.rb`. A estratégia é criar um `data_type: "boolean_virtual"` para encapsular esse padrão sem tocar no fluxo genérico de filtros.

No frontend, o `inputType: 'booleanSelect'` já existe e renderiza um dropdown "Sim / Não".

## Arquivos a modificar

### 1. `lib/filters/filter_keys.yml`

Adicionar após `last_activity_at` no bloco `conversations`:

```yaml
has_unread_messages:
  attribute_type: "standard"
  data_type: "boolean_virtual"
  filter_operators:
    - "equal_to"
```

### 2. `app/helpers/filters/filter_helper.rb`

Em `handle_standard_attributes()`, adicionar case para o novo data_type antes do `else` genérico:

```ruby
when 'boolean_virtual'
  virtual_boolean_filter(query_hash)
```

Adicionar o método privado:

```ruby
def virtual_boolean_filter(query_hash)
  is_true    = query_hash['values'].first.to_s == 'true'
  negate     = query_hash[:filter_operator] == 'not_equal_to'
  has_unread = is_true ^ negate

  if has_unread
    "(conversations.agent_last_seen_at IS NULL " \
      "OR conversations.last_activity_at > conversations.agent_last_seen_at) " \
      "#{query_hash[:query_operator]}"
  else
    "(conversations.agent_last_seen_at IS NOT NULL " \
      "AND conversations.last_activity_at <= conversations.agent_last_seen_at) " \
      "#{query_hash[:query_operator]}"
  end
end
```

### 3. `app/javascript/dashboard/components-next/filter/helper/filterHelper.js`

Adicionar a constante em `CONVERSATION_ATTRIBUTES`:

```javascript
HAS_UNREAD_MESSAGES: 'has_unread_messages',
```

### 4. `app/javascript/dashboard/components-next/filter/provider.js`

Adicionar o filtro na lista `filterTypes`, próximo dos outros filtros de data:

```javascript
{
  attributeKey: CONVERSATION_ATTRIBUTES.HAS_UNREAD_MESSAGES,
  value: CONVERSATION_ATTRIBUTES.HAS_UNREAD_MESSAGES,
  attributeName: t('FILTER.ATTRIBUTES.HAS_UNREAD_MESSAGES'),
  label: t('FILTER.ATTRIBUTES.HAS_UNREAD_MESSAGES'),
  inputType: 'booleanSelect',
  options: [
    { id: 'true',  name: t('FILTER.BOOLEAN_OPTIONS.TRUE') },
    { id: 'false', name: t('FILTER.BOOLEAN_OPTIONS.FALSE') },
  ],
  dataType: 'text',
  filterOperators: equalityOperators.value,
  attributeModel: 'standard',
},
```

### 5. `app/javascript/dashboard/store/modules/conversations/helpers/filterHelpers.js`

Adicionar case no `matchesCondition()` para avaliação client-side:

```javascript
case 'has_unread_messages': {
  const hasUnread =
    !conversation.agent_last_seen_at ||
    conversation.last_activity_at > conversation.agent_last_seen_at;
  const filterVal = filterValue === 'true' || filterValue === true;
  return filterOperator === 'equal_to' ? hasUnread === filterVal : hasUnread !== filterVal;
}
```

### 6. i18n — `advancedFilters.json` (en e pt_BR)

Em `ATTRIBUTES` adicionar:
```json
"HAS_UNREAD_MESSAGES": "Has unread messages"     // en
"HAS_UNREAD_MESSAGES": "Tem mensagens não lidas" // pt_BR
```

Verificar se `BOOLEAN_OPTIONS` já existe. Se não, adicionar:
```json
"BOOLEAN_OPTIONS": {
  "TRUE": "Yes",   // en → pt_BR: "Sim"
  "FALSE": "No"    // en → pt_BR: "Não"
}
```

## Verificação

1. Abrir filtros → confirmar que "Tem mensagens não lidas" aparece na lista de atributos
2. Selecionar "Sim" → aplicar → confirmar que só conversas com badge de não lidas aparecem
3. Selecionar "Não" → aplicar → confirmar que só conversas já lidas aparecem
4. Combinar com outros filtros (ex: Status = Aberta + Tem não lidas = Sim) → confirmar que AND funciona corretamente
