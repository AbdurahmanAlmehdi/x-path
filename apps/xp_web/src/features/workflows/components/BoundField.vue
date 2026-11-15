<script setup lang="ts">
import { ref, watch } from 'vue'

/**
 * A text field of the visual editor bound to a value of the document. While
 * it has focus it keeps what is typed (`prod, ` reads as `[prod]`, and the
 * comma would go); it shows the document's value again once it loses focus.
 */
const props = withDefaults(
  defineProps<{
    label: string
    value: string
    placeholder?: string
    disabled?: boolean
    code?: boolean
    multiline?: boolean
  }>(),
  { placeholder: '', disabled: false, code: false, multiline: false },
)

const emit = defineEmits<{ change: [text: string] }>()

const text = ref(props.value)
const focused = ref(false)

watch(
  () => props.value,
  (value) => {
    if (!focused.value) text.value = value
  },
)

function onInput(event: Event) {
  text.value = (event.target as HTMLInputElement | HTMLTextAreaElement).value
  emit('change', text.value)
}

function onBlur() {
  focused.value = false
  text.value = props.value
}
</script>

<template>
  <label class="field">
    <span class="xp-type-label">{{ label }}</span>
    <textarea
      v-if="multiline"
      :value="text"
      :placeholder="placeholder"
      :disabled="disabled"
      rows="3"
      @focus="focused = true"
      @blur="onBlur"
      @input="onInput"
    ></textarea>
    <input
      v-else
      type="text"
      :class="{ mono: code }"
      :value="text"
      :placeholder="placeholder"
      :disabled="disabled"
      autocomplete="off"
      spellcheck="false"
      @focus="focused = true"
      @blur="onBlur"
      @input="onInput"
    />
  </label>
</template>
