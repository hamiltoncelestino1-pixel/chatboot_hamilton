<script setup>
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col items-center justify-center flex-1 gap-4 p-8 text-center"
  >
    <span
      class="i-lucide-columns-3 size-16 text-slate-300 dark:text-slate-600"
    />
    <div>
      <h3 class="text-base font-semibold text-slate-700 dark:text-slate-200">
        {{ t('KANBAN.EMPTY_STATE.TITLE') }}
      </h3>
      <p class="mt-1 text-sm text-slate-500 dark:text-slate-400 max-w-xs">
        {{ t('KANBAN.EMPTY_STATE.DESCRIPTION') }}
      </p>
    </div>
    <router-link
      :to="{ name: 'pipelines_list' }"
      class="px-4 py-2 text-sm font-medium text-white bg-woot-500 rounded-lg hover:bg-woot-600 transition-colors"
    >
      {{ t('KANBAN.EMPTY_STATE.BUTTON') }}
    </router-link>
  </div>
</template>
