# Task 01: Fix WhatsApp Template Header TEXT Variables — ✅ CONCLUÍDA

## Problema

Templates WhatsApp com header do tipo TEXT contendo variáveis como `{{1}}`, `{{2}}` não geram campos de preenchimento no frontend. O resultado é que as variáveis são enviadas literalmente ao cliente (ex: "Olá {{1}}").

## Diagnóstico

O fluxo de variáveis no BODY já funciona de ponta a ponta. O código simplesmente ignora o componente HEADER quando ele é do tipo `TEXT` ao construir os parâmetros do template.

**Raiz: frontend-only.** O backend (`template_processor_service.rb`) já tem um fallback genérico que envia qualquer chave não-media do header como parâmetro de texto — não precisa de alteração.

## Arquivos a modificar

### 1. `app/javascript/dashboard/helper/templateHelper.js`

Na função `buildTemplateParameters()`, adicionar extração de variáveis do HEADER TEXT após o bloco de BODY:

```javascript
const headerComponent = components.find(c => c.type === COMPONENT_TYPES.HEADER);
if (headerComponent?.format === 'TEXT' && headerComponent.text?.includes('{{')) {
  const headerVars = [...new Set(headerComponent.text.match(/{{\d+}}/g) || [])];
  if (headerVars.length) {
    allVariables.header = {};
    headerVars.forEach(v => {
      const key = v.replace(/{{|}}/g, '');
      allVariables.header[key] = '';
    });
  }
}
```

### 2. `app/javascript/dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue`

**a) Corrigir `hasVariables` computed** para incluir verificação do header TEXT:

```javascript
const hasVariables = computed(() => {
  const bodyHasVars = bodyText.value?.match(/{{([^}]+)}}/g) !== null;
  const headerHasVars =
    headerComponent.value?.format === 'TEXT' &&
    !!headerComponent.value?.text?.match(/{{([^}]+)}}/g);
  return bodyHasVars || headerHasVars;
});
```

**b) Corrigir `isFormInvalid` computed** para validar variáveis do header:

```javascript
const headerTextVars = processedParams.value.header;
const hasUnfilledHeaderVars =
  headerTextVars &&
  !hasMediaHeader.value &&
  Object.values(headerTextVars).some(v => !v);

if (hasUnfilledHeaderVars) return true;
```

**c) Adicionar inputs de variáveis do header TEXT** no template HTML, antes da seção de BODY (seguindo o mesmo padrão visual dos inputs de body):

```html
<template v-if="!hasMediaHeader && processedParams.header">
  <p class="...">{{ $t('WHATSAPP_TEMPLATES.PARSER.HEADER_VARIABLES') }}</p>
  <div v-for="(value, key) in processedParams.header" :key="`header_${key}`">
    <input
      :value="value"
      @input="updateHeaderVariable(key, $event.target.value)"
      :placeholder="`{{${key}}}`"
    />
  </div>
</template>
```

**d) Adicionar método `updateHeaderVariable`:**

```javascript
const updateHeaderVariable = (key, value) => {
  processedParams.value.header[key] = value;
};
```

### 3. i18n

Localizar o arquivo correto para `WHATSAPP_TEMPLATES.PARSER` (provavelmente `whatsappTemplates.json` em `app/javascript/dashboard/i18n/locale/`).

Adicionar em `en`:
```json
"HEADER_VARIABLES": "Header variables"
```

Adicionar em `pt_BR`:
```json
"HEADER_VARIABLES": "Variáveis do cabeçalho"
```

## Verificação

1. Usar um template com `HEADER` do tipo TEXT contendo `{{1}}` no Meta Business Manager
2. Abrir o seletor de templates na conversa → confirmar que aparece campo de input para a variável do header
3. Preencher a variável e enviar → confirmar que o texto final chega ao cliente com `{{1}}` substituído
4. Confirmar que templates sem variável no header continuam funcionando normalmente
