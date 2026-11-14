<script setup lang="ts">
import { computed } from 'vue'

import type { JobState, RunState, StepState } from '@/api/client'

import { statusOf } from './format'

const props = defineProps<{ state: JobState | RunState | StepState }>()

const status = computed(() => statusOf(props.state))
</script>

<template>
  <span class="badge xp-type-label" :class="status.tone" :data-state="state">{{ status.label }}</span>
</template>

<style scoped>
.badge {
  display: inline-flex;
  align-items: center;
  height: 20px;
  padding: 0 var(--xp-space-6);
  border-radius: var(--xp-radius-sm);
  white-space: nowrap;
  color: var(--xp-color-status-neutral-on-container);
  background: var(--xp-color-status-neutral-container);
}

.info {
  color: var(--xp-color-status-info-on-container);
  background: var(--xp-color-status-info-container);
}

.attention {
  color: var(--xp-color-status-attention-on-container);
  background: var(--xp-color-status-attention-container);
}

.positive {
  color: var(--xp-color-status-positive-on-container);
  background: var(--xp-color-status-positive-container);
}

.negative {
  color: var(--xp-color-status-negative-on-container);
  background: var(--xp-color-status-negative-container);
}

.caution {
  color: var(--xp-color-status-caution-on-container);
  background: var(--xp-color-status-caution-container);
}
</style>
