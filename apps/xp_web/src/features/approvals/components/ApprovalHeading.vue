<script setup lang="ts">
import type { Approval } from '@/api/client'
import Badge from '@/ui/Badge.vue'
import { formatTime } from '@/ui/format'

import { approvalStateLine, approvalStatus, approvalTitle, expiresSoon } from '../labels'

defineProps<{ approval: Approval }>()
</script>

<template>
  <div class="state-line">
    <Badge :status="approvalStatus(approval.state)" />
    <span
      class="muted"
      :class="{ soon: approval.state === 'pending' && expiresSoon(approval) }"
      data-testid="approval-state-line"
    >
      {{ approvalStateLine(approval) }}
    </span>
  </div>
  <h2 class="xp-type-headline title">{{ approvalTitle(approval) }}</h2>
  <p class="muted">asked at {{ formatTime(approval.createdAt) }}</p>
</template>

<style scoped>
.state-line {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-8);
  margin-bottom: var(--xp-space-8);
}

.soon {
  color: var(--xp-color-status-caution-on-container);
}

.title {
  margin: 0 0 var(--xp-space-4);
  overflow-wrap: anywhere;
}
</style>
