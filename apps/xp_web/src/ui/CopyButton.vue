<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'

const props = defineProps<{ label: string; text: string }>()

/** Whether it says "Copied", for a moment after a copy. */
const copied = ref(false)
let reset: ReturnType<typeof setTimeout> | undefined

async function copy() {
  try {
    await navigator.clipboard.writeText(props.text)
  } catch {
    // The browser refused the clipboard: nothing was copied.
    return
  }
  copied.value = true
  clearTimeout(reset)
  reset = setTimeout(() => {
    copied.value = false
  }, 1200)
}

onBeforeUnmount(() => clearTimeout(reset))
</script>

<template>
  <button type="button" @click="copy">{{ copied ? 'Copied' : label }}</button>
</template>
