<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'

import { plainText } from '@/ui/format'

import { useJobLogStore } from '../stores/log'

// The store grows one list of lines in place, so the view reads it from the
// store: a prop of the same list would not tell it a line came.
const log = useJobLogStore()

const box = ref<HTMLElement | null>(null)
/** Whether the view keeps the newest line in sight. */
const follow = ref(true)

function atBottom(element: HTMLElement): boolean {
  return element.scrollHeight - element.scrollTop - element.clientHeight < 4
}

/** Scrolling up to read stops following; scrolling back to the end follows again. */
function scrolled() {
  if (box.value) follow.value = atBottom(box.value)
}

function toEnd() {
  if (box.value) box.value.scrollTop = box.value.scrollHeight
}

function followAgain() {
  follow.value = true
  toEnd()
}

watch(
  () => log.lines.length,
  async () => {
    if (!follow.value) return
    await nextTick()
    toEnd()
  },
)
</script>

<template>
  <div class="log-view">
    <div class="toolbar">
      <span class="xp-type-label muted" data-testid="log-count">
        {{ log.lines.length === 1 ? '1 line' : `${log.lines.length} lines` }}<template v-if="log.following"> · live</template>
      </span>
      <button type="button" :aria-pressed="follow" @click="followAgain">Follow</button>
    </div>
    <div ref="box" class="log" role="log" tabindex="0" aria-label="Job log" @scroll="scrolled">
      <p v-if="log.lines.length === 0" class="empty">No output yet</p>
      <div
        v-for="line in log.lines"
        :key="line.seq"
        class="line"
        :class="{ stderr: line.stream === 'stderr' }"
        :data-seq="line.seq"
      >
        <span class="gutter" aria-hidden="true">{{ line.seq }}</span><span class="text">{{ plainText(line.text) }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--xp-space-8);
  margin-bottom: var(--xp-space-6);
}

button[aria-pressed='true'] {
  background: var(--xp-color-surface-selected);
}

.log {
  height: min(60vh, 640px);
  overflow: auto;
  padding: var(--xp-space-8) 0;
  font: var(--xp-type-code);
  color: var(--xp-color-log-text);
  background: var(--xp-color-log-surface);
  border-radius: var(--xp-radius-md);
  user-select: text;
}

.empty {
  margin: 0;
  padding: 0 var(--xp-space-12);
  color: var(--xp-color-log-dim);
}

.line {
  display: flex;
  padding: 0 var(--xp-space-12) 0 0;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.line.stderr {
  background: var(--xp-color-log-stderr-row);
}

.gutter {
  flex: none;
  width: 5ch;
  margin-right: var(--xp-space-12);
  text-align: right;
  color: var(--xp-color-log-gutter);
  user-select: none;
}

.text {
  min-width: 0;
}
</style>
