<script setup lang="ts">
import CopyButton from './CopyButton.vue'

defineProps<{
  /** What it is, over the well. */
  label: string
  /** The text to show and copy: a secret shown once, or a command. */
  text: string
  /** The label of its copy button. */
  copyLabel: string
}>()
</script>

<template>
  <div class="field">
    <span class="xp-type-label">{{ label }}</span>
    <div class="well">
      <code>{{ text }}</code>
      <CopyButton :label="copyLabel" :text="text" />
    </div>
  </div>
</template>
