<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'

import type { EditorIssue, YamlEditorHandle } from './yamlEditor'

/**
 * The YAML of the workflow in CodeMirror 6, which this component loads with
 * a dynamic import when it first mounts: none of it is in the entry chunk.
 * Issues are marked on their lines; [reveal] puts the cursor on one.
 */
const props = defineProps<{
  text: string
  readOnly: boolean
  issues: EditorIssue[]
  reveal: { line: number; column: number; seq: number } | null
}>()

const emit = defineEmits<{ change: [text: string] }>()

const host = ref<HTMLElement | null>(null)
const editor = shallowRef<YamlEditorHandle | null>(null)
const failed = ref(false)
let gone = false

onMounted(async () => {
  try {
    const { createYamlEditor } = await import('./yamlEditor')
    if (gone || !host.value) return
    editor.value = createYamlEditor(host.value, {
      text: props.text,
      readOnly: props.readOnly,
      label: 'YAML',
      onChange: (text) => emit('change', text),
    })
    editor.value.setIssues(props.issues)
  } catch {
    failed.value = true
  }
})

onBeforeUnmount(() => {
  gone = true
  editor.value?.destroy()
  editor.value = null
})

watch(
  () => props.text,
  (text) => editor.value?.setText(text),
)
watch(
  () => props.readOnly,
  (readOnly) => editor.value?.setReadOnly(readOnly),
)
watch(
  () => props.issues,
  (issues) => editor.value?.setIssues(issues),
)
watch(
  () => props.reveal,
  (reveal) => {
    if (reveal) editor.value?.reveal(reveal.line, reveal.column)
  },
)
</script>

<template>
  <div class="yaml-editor">
    <p v-if="failed" class="alert" role="alert">The editor could not load. Reload the page to try again.</p>
    <p v-else-if="!editor" class="muted loading">Loading the editor…</p>
    <!-- CodeMirror renders in a shadow root of this element (yamlEditor.ts). -->
    <div ref="host"></div>
  </div>
</template>

<style scoped>
.yaml-editor {
  min-width: 0;
}

.loading {
  padding: var(--xp-space-8);
}
</style>
