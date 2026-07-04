# Task: Restrição de Acesso por Time para Agentes

## Problema

Agentes visualizam todas as conversas das inboxes às quais pertencem, mesmo que essas conversas pertençam a times dos quais não fazem parte. O objetivo é permitir que admins ativem uma restrição onde agentes veem **apenas conversas atribuídas aos seus times**.

## Diagnóstico

O controle de visibilidade de conversas por agente passa por `Conversations::PermissionFilterService#accessible_conversations`, que hoje filtra apenas por inbox membership. Times já existem no sistema (`team_id` em conversas, `team_members` como join table), mas não são usados nesse filtro.

A solução é um setting de conta (`enforce_team_based_access`) com toggle na UI de configurações — seguindo o padrão já existente de `AudioTranscription.vue`.

Sem migração de banco necessária: o campo `settings` em `accounts` é jsonb com `additionalProperties: true` no schema.

## Arquivos a modificar

### Backend

#### 1. `app/models/concerns/account_settings_schema.rb`

Adicionar a propriedade no schema JSON (dentro de `'properties':`):

```ruby
'enforce_team_based_access': { 'type': %w[boolean null] },
```

#### 2. `app/models/account.rb`

Adicionar `store_accessor` após os já existentes:

```ruby
store_accessor :settings, :enforce_team_based_access
```

#### 3. `app/services/conversations/permission_filter_service.rb`

Substituir `accessible_conversations` e adicionar método privado `team_scoped_conversations`:

```ruby
def accessible_conversations
  if account.enforce_team_based_access
    team_scoped_conversations
  else
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
  end
end

def team_scoped_conversations
  team_ids = user.teams.where(account_id: account.id).pluck(:id)
  conversations.where(team_id: team_ids)
end
```

#### 4. `app/controllers/api/v1/accounts_controller.rb`

Adicionar `:enforce_team_based_access` em `permitted_settings_attributes` (~linha 122):

```ruby
def permitted_settings_attributes
  [:auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting,
   :audio_transcriptions, :auto_resolve_label, :enforce_team_based_access]
end
```

### Frontend

#### 5. `app/javascript/dashboard/routes/dashboard/settings/account/components/RestrictAgentsByTeam.vue`

Novo componente — seguir exatamente o padrão de `AudioTranscription.vue`:

```vue
<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const isEnabled = ref(false);
const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    const { enforce_team_based_access } = currentAccount.value?.settings || {};
    isEnabled.value = !!enforce_team_based_access;
  },
  { deep: true, immediate: true }
);

const toggleSetting = async () => {
  try {
    await updateAccount({ enforce_team_based_access: isEnabled.value });
    useAlert(t('GENERAL_SETTINGS.FORM.RESTRICT_AGENTS_BY_TEAM.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.RESTRICT_AGENTS_BY_TEAM.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.RESTRICT_AGENTS_BY_TEAM.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.RESTRICT_AGENTS_BY_TEAM.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggleSetting" />
      </div>
    </template>
  </SectionLayout>
</template>
```

#### 6. `app/javascript/dashboard/routes/dashboard/settings/account/Index.vue`

Importar e adicionar o componente após `<AudioTranscription />`:

```javascript
import RestrictAgentsByTeam from './components/RestrictAgentsByTeam.vue';
```

```html
<!-- No template, após <AudioTranscription />: -->
<RestrictAgentsByTeam />
```

#### 7. i18n — `generalSettings.json` (en e pt_BR)

Em `FORM`, adicionar:

```json
// en
"RESTRICT_AGENTS_BY_TEAM": {
  "TITLE": "Restrict agents by team",
  "NOTE": "When enabled, agents can only view conversations assigned to their teams. Conversations without a team are only visible to administrators.",
  "API": {
    "SUCCESS": "Team access restriction updated successfully.",
    "ERROR": "Failed to update team access restriction."
  }
}

// pt_BR
"RESTRICT_AGENTS_BY_TEAM": {
  "TITLE": "Restringir agentes por time",
  "NOTE": "Quando ativado, agentes visualizam apenas conversas atribuídas aos seus times. Conversas sem time são visíveis somente para administradores.",
  "API": {
    "SUCCESS": "Restrição de acesso por time atualizada com sucesso.",
    "ERROR": "Falha ao atualizar restrição de acesso por time."
  }
}
```

## Pontos de atenção

| Cenário | Comportamento quando ativado |
|---|---|
| Conversa sem `team_id` | Invisível para agentes (só admins veem) |
| Agente sem nenhum time | Vê zero conversas |
| Admin | Sempre vê tudo (não afetado — linha 11 do service) |
| Setting desativado | Comportamento original preservado (filtro por inbox) |

## Verificação

1. Ir em Configurações → Conta → confirmar que o toggle "Restringir agentes por time" aparece
2. Ativar → logar como agente membro do Time A → confirmar que só conversas do Time A aparecem
3. Confirmar que conversas sem `team_id` não aparecem para agentes
4. Confirmar que admins continuam vendo tudo independente do setting
5. Desativar → confirmar que o comportamento original retorna (filtro por inbox)
