<script setup>
import TaskList from 'dashboard/components-next/Tasks/TaskList.vue';

defineProps({
  contactId: { type: Number, required: true },
});
</script>

<template>
  <TaskList :contact-id="contactId" />
</template>
