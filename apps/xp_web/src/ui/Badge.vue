<script setup lang="ts">
import type { StatusLabel } from './format'

defineProps<{ status: StatusLabel }>()
</script>

<template>
  <span class="badge xp-type-label" :class="status.tone">{{ status.label }}</span>
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

.merged {
  color: var(--xp-color-status-merged-on-container);
  background: var(--xp-color-status-merged-container);
}
</style>
