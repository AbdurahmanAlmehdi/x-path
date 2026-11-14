<script setup lang="ts">
import { computed } from 'vue'

import type { JobState, RunState, StepState } from '@/api/client'

import Badge from './Badge.vue'
import { statusOf } from './format'

const props = defineProps<{ state: JobState | RunState | StepState }>()

const status = computed(() => statusOf(props.state))
</script>

<template>
  <Badge :status="status" :data-state="state" />
</template>
