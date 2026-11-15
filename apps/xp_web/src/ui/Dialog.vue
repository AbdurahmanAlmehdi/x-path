<script setup lang="ts">
import { onMounted, ref } from 'vue'

defineProps<{
  /** The title of the dialog, also its accessible name. */
  title: string
}>()

const emit = defineEmits<{ close: [] }>()

const dialog = ref<HTMLElement | null>(null)

onMounted(() => dialog.value?.focus())

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') emit('close')
}
</script>

<template>
  <div class="scrim" @click.self="emit('close')">
    <div
      ref="dialog"
      class="dialog"
      role="dialog"
      aria-modal="true"
      :aria-label="title"
      tabindex="-1"
      @keydown="onKeydown"
    >
      <div class="body">
        <h2 class="xp-type-headline">{{ title }}</h2>
        <slot />
      </div>
      <footer class="footer">
        <slot name="footer" />
      </footer>
    </div>
  </div>
</template>

<style scoped>
.scrim {
  position: fixed;
  inset: 0;
  z-index: 10;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--xp-space-32) var(--xp-space-16) var(--xp-space-16);
  overflow-y: auto;
  background: var(--xp-color-scrim-default);
}

.dialog {
  width: min(560px, 100%);
  background: var(--xp-color-surface-overlay);
  border: var(--xp-border-width-hairline) solid var(--xp-color-border-strong);
  border-radius: var(--xp-radius-lg);
  box-shadow: var(--xp-elevation-3);
}

.dialog:focus {
  outline: none;
}

.body {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-12);
  padding: var(--xp-space-16) var(--xp-space-20);
}

.body h2 {
  margin: 0;
}

.footer {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-items: center;
  gap: var(--xp-space-8);
  padding: var(--xp-space-12) var(--xp-space-20);
  border-top: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
}
</style>
