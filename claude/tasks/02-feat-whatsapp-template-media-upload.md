# Task 02: Upload Direto de Mídia em Templates WhatsApp — ✅ CONCLUÍDA

## Problema

Templates com header de mídia (IMAGE, VIDEO, DOCUMENT) só aceitam uma URL pública colada manualmente. Isso é inviável no dia a dia. O Chatwoot já hospeda mídia internamente via ActiveStorage — o objetivo é permitir upload direto do arquivo na própria tela de envio do template.

## Diagnóstico

O endpoint de upload **já existe**: `POST /api/v1/accounts/:account_id/upload`
(implementado em `app/controllers/api/v1/accounts/upload_controller.rb`)

Retorna: `{ file_url, blob_id }`

A função `uploadFile()` em `app/javascript/dashboard/helper/uploadHelper.js` já encapsula essa chamada.

**Mudança necessária: apenas frontend**, plugando o fluxo de upload existente na UI do template. O campo de URL atual deve ser mantido como alternativa (para quem queira colar um link externo).

## Arquivo a modificar

### `app/javascript/dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue`

**a) Importar `uploadFile`:**

```javascript
import { uploadFile } from 'dashboard/helper/uploadHelper';
```

**b) Adicionar estado e getter do accountId:**

```javascript
const isUploading = ref(false);
const accountId = useMapGetter('getCurrentAccountId'); // já disponível no contexto
```

**c) Adicionar `acceptedMediaTypes` computed** baseado no formato do header:

```javascript
const acceptedMediaTypes = computed(() => {
  const format = headerComponent.value?.format;
  if (format === 'IMAGE') return 'image/*';
  if (format === 'VIDEO') return 'video/*';
  if (format === 'DOCUMENT') return '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx';
  return '*';
});
```

**d) Adicionar método `handleMediaUpload`:**

```javascript
const handleMediaUpload = async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  isUploading.value = true;
  try {
    const { fileUrl } = await uploadFile(file, accountId.value);
    updateMediaUrl(fileUrl);
  } finally {
    isUploading.value = false;
  }
};
```

**e) Substituir a seção de media URL atual** por UI com upload + URL como fallback:

```html
<template v-if="hasMediaHeader">
  <!-- Opção 1: Upload direto -->
  <label class="flex items-center justify-center w-full p-3 border-2 border-dashed rounded-lg cursor-pointer border-slate-300 hover:border-woot-500">
    <input
      type="file"
      class="hidden"
      :accept="acceptedMediaTypes"
      @change="handleMediaUpload"
    />
    <span v-if="isUploading" class="text-sm text-slate-500">
      {{ $t('WHATSAPP_TEMPLATES.PARSER.UPLOADING') }}
    </span>
    <span v-else class="text-sm text-slate-500">
      {{ $t('WHATSAPP_TEMPLATES.PARSER.UPLOAD_FILE') }}
    </span>
  </label>

  <!-- Separador -->
  <p class="text-xs text-center text-slate-400 my-1">
    {{ $t('WHATSAPP_TEMPLATES.PARSER.OR') }}
  </p>

  <!-- Opção 2: Colar URL -->
  <input
    type="url"
    :value="processedParams.header?.media_url"
    @input="updateMediaUrl($event.target.value)"
    :placeholder="$t('WHATSAPP_TEMPLATES.PARSER.MEDIA_URL_LABEL')"
    class="..."
  />

  <!-- Preview da mídia definida -->
  <p v-if="processedParams.header?.media_url" class="text-xs text-slate-500 truncate mt-1">
    {{ processedParams.header.media_url }}
  </p>
</template>
```

## i18n

Localizar o arquivo correto para `WHATSAPP_TEMPLATES.PARSER` e adicionar:

Em `en`:
```json
"UPLOAD_FILE": "Click to upload file",
"UPLOADING": "Uploading...",
"OR": "or"
```

Em `pt_BR`:
```json
"UPLOAD_FILE": "Clique para enviar arquivo",
"UPLOADING": "Enviando...",
"OR": "ou"
```

## Observação sobre URLs públicas

O `file_url` retornado pelo endpoint é uma URL ActiveStorage do próprio servidor (`/rails/active_storage/blobs/redirect/...`). Em produção com domínio público, o WhatsApp consegue acessar essa URL normalmente. Em desenvolvimento local (localhost), o WhatsApp não conseguirá — mas isso é limitação esperada do ambiente de dev.

## Verificação

1. Abrir template com header IMAGE/VIDEO/DOCUMENT
2. Confirmar que aparece área de upload (dashed border) além do campo de URL
3. Fazer upload de uma imagem → confirmar que o campo é preenchido automaticamente com a URL retornada
4. Enviar o template → confirmar que a mídia chega corretamente na conversa do WhatsApp
5. Confirmar que colar URL manualmente ainda funciona como antes
