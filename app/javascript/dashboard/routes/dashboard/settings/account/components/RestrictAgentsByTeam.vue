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
