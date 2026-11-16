<script setup lang="ts">
import { computed } from 'vue'

import { diffLines } from '../diff'

/**
 * [after] against [before], a line each, as the Mac app's `XpDiffView`:
 * added lines on the positive tint, removed ones on the negative. With no
 * change it says so, and still shows the text.
 */
const props = defineProps<{ before: string; after: string }>()

const lines = computed(() => diffLines(props.before, props.after))
const unchanged = computed(() => lines.value.every((line) => line.kind === 'same'))
const marks = { same: ' ', added: '+', removed: '-' } as const
</script>

<template>
  <p v-if="unchanged" class="muted">No changes.</p>
  <pre class="diff mono" data-testid="diff"><span
      v-for="(line, index) in lines"
      :key="index"
      class="line"
      :class="line.kind"
    >{{ marks[line.kind] }}{{ line.text }}
</span></pre>
</template>

<style scoped>
.diff {
  max-height: 60vh;
  margin: 0;
  padding: var(--xp-space-6) 0;
  overflow: auto;
  background: var(--xp-color-surface-sunken);
  border: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
  border-radius: var(--xp-radius-md);
}

.line {
  display: block;
  padding: 0 var(--xp-space-10);
  color: var(--xp-color-text-secondary);
  white-space: pre;
}

.added {
  color: var(--xp-color-status-positive-on-container);
  background: var(--xp-color-status-positive-container);
}

.removed {
  color: var(--xp-color-status-negative-on-container);
  background: var(--xp-color-status-negative-container);
}
</style>
