# Task: Operador "É igual à" para filtros de data

## Problema

Os campos de data no filtro avançado (`Criado em`, `Última atividade`) só oferecem "É maior que", "É menor que" e "É X dias antes". Não há como filtrar por uma data exata.

## Diagnóstico

O operador `equal_to` **já existe** no sistema (`FILTER_OPS.EQUAL_TO` em `operators.js`). Ele simplesmente não foi adicionado à lista de operadores disponíveis para campos `date`. O backend já roteia `equal_to` corretamente — o cast `(conversations.created_at)::date IN (:value_0)` funciona para comparação de data exata no PostgreSQL sem nenhuma alteração adicional.

## Arquivos a modificar

### 1. `app/javascript/dashboard/components-next/filter/operators.js`

No computed `dateOperators`, adicionar `EQUAL_TO` como primeira opção:

```javascript
// Antes:
const dateOperators = computed(() => [IS_GREATER_THAN, IS_LESS_THAN, DAYS_BEFORE]);

// Depois:
const dateOperators = computed(() => [EQUAL_TO, IS_GREATER_THAN, IS_LESS_THAN, DAYS_BEFORE]);
```

### 2. `lib/filters/filter_keys.yml`

Nos blocos `created_at` e `last_activity_at` (tanto em `conversations` quanto em `contacts`), adicionar `equal_to` à lista de `filter_operators`:

```yaml
created_at:
  attribute_type: "standard"
  data_type: "date"
  filter_operators:
    - "equal_to"          # <- adicionar
    - "is_greater_than"
    - "is_less_than"
    - "days_before"
```

### 3. `app/javascript/dashboard/store/modules/conversations/helpers/filterHelpers.js`

No `matchesCondition()`, adicionar o case `equal_to` dentro do bloco de datas (junto com `is_greater_than` / `is_less_than`):

```javascript
case 'equal_to':
  return compareDates(conversationValue, filterValue, (a, b) => {
    return new Date(a).toDateString() === new Date(b).toDateString();
  });
```

## Notas

- **i18n:** O label `"equal_to": "Equal to"` já existe em `advancedFilters.json` (en e pt_BR). Nada a adicionar.
- O input renderizado para `equal_to` em campos `date` será um date picker (mesmo que já é usado para os outros operadores de data). Nenhuma alteração no componente de UI é necessária.

## Verificação

1. Abrir filtros → campo "Criado em" → confirmar que "É igual à" aparece como primeira opção
2. Selecionar uma data e aplicar → confirmar que só conversas criadas naquele dia aparecem
3. Repetir com "Última atividade"
4. Confirmar que os outros operadores (`>`, `<`, `X dias antes`) continuam funcionando normalmente
