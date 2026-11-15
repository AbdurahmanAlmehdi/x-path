<script setup lang="ts">
import { computed } from 'vue'

import type { StepKeySchema } from '@/api/client'

import { formatYamlValue, parseYamlValue } from '../document'
import BoundField from './BoundField.vue'

/**
 * One key of a step's `with`, edited by its type as in the Mac app: Default,
 * On and Off for a boolean, a menu for a string with options, checkboxes for
 * a list with options, YAML text for the rest and for a placeholder. A key
 * the step type needs is marked, and says so while it is missing. It reports
 * the new value, or `undefined` to leave the key out.
 */
const props = defineProps<{
  name: string
  /** What the engine says of the key; absent for one it does not know. */
  keySchema?: StepKeySchema
  given: boolean
  value: unknown
  disabled: boolean
}>()

const emit = defineEmits<{ change: [value: unknown] }>()

const placeholder = computed(() => typeof props.value === 'string' && props.value.includes('${{'))
const defaultLabel = computed(() =>
  props.keySchema?.default === undefined || props.keySchema.default === null
    ? 'Default'
    : `Default (${formatYamlValue(props.keySchema.default)})`,
)
const options = computed(() => props.keySchema?.options)

const kind = computed<'boolean' | 'choice' | 'list' | 'text'>(() => {
  const value = props.value
  const absent = value === undefined || value === null
  if (placeholder.value || !props.keySchema) return 'text'
  if (props.keySchema.type === 'boolean' && (absent || typeof value === 'boolean')) return 'boolean'
  if (props.keySchema.type === 'string' && options.value && (absent || typeof value === 'string')) return 'choice'
  if (props.keySchema.type === 'list' && options.value && (absent || Array.isArray(value))) return 'list'
  return 'text'
})

const choices = computed(() => {
  const value = props.value
  const listed = options.value ?? []
  return typeof value === 'string' && !listed.includes(value) ? [...listed, value] : listed
})
const chosen = computed(() => (Array.isArray(props.value) ? props.value : []))
const missing = computed(() => props.keySchema?.required === true && !props.given)
const text = computed(() => (props.given ? formatYamlValue(props.value) : ''))

function onBoolean(event: Event) {
  const value = (event.target as HTMLSelectElement).value
  emit('change', value === '' ? undefined : value === 'true')
}

function onChoice(event: Event) {
  const value = (event.target as HTMLSelectElement).value
  emit('change', value === '' ? undefined : value)
}

function onOption(option: string, on: boolean) {
  emit(
    'change',
    (options.value ?? []).filter((each) => (each === option ? on : chosen.value.includes(each))),
  )
}

function onText(typed: string) {
  emit('change', typed.trim() === '' ? undefined : parseYamlValue(typed))
}
</script>

<template>
  <div class="with-field" :data-key="name">
    <div class="key" :title="keySchema?.description">
      <code>{{ name }}</code><span v-if="keySchema?.required" class="needed-mark" aria-label="needed"> *</span>
    </div>
    <div class="value">
      <select
        v-if="kind === 'boolean'"
        :aria-label="name"
        :value="typeof value === 'boolean' ? String(value) : ''"
        :disabled="disabled"
        @change="onBoolean"
      >
        <option value="">{{ defaultLabel }}</option>
        <option value="true">On</option>
        <option value="false">Off</option>
      </select>
      <select
        v-else-if="kind === 'choice'"
        :aria-label="name"
        class="mono"
        :value="typeof value === 'string' ? value : ''"
        :disabled="disabled"
        @change="onChoice"
      >
        <option value="">{{ defaultLabel }}</option>
        <option v-for="option in choices" :key="option" :value="option">{{ option }}</option>
      </select>
      <fieldset v-else-if="kind === 'list'" class="options" :aria-label="name">
        <label v-for="option in options" :key="option" class="option">
          <input
            type="checkbox"
            :checked="chosen.includes(option)"
            :disabled="disabled"
            @change="onOption(option, ($event.target as HTMLInputElement).checked)"
          />
          <code>{{ option }}</code>
        </label>
      </fieldset>
      <BoundField
        v-else
        :label="name"
        class="text"
        :value="text"
        :placeholder="keySchema?.description ?? 'YAML value'"
        :disabled="disabled"
        code
        @change="onText"
      />
      <p v-if="missing" class="needed">Needed</p>
    </div>
  </div>
</template>

<style scoped>
.with-field {
  display: grid;
  grid-template-columns: minmax(96px, 150px) minmax(0, 1fr);
  gap: var(--xp-space-8);
  align-items: start;
}

.key {
  padding-top: var(--xp-space-6);
  overflow-wrap: anywhere;
}

.needed-mark,
.needed {
  color: var(--xp-color-negative-default);
}

.needed {
  margin: var(--xp-space-2) 0 0;
  font: var(--xp-type-caption);
}

.value select {
  width: 100%;
}

.text :deep(input) {
  width: 100%;
}

.text :deep(.xp-type-label) {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
}

.options {
  display: flex;
  flex-wrap: wrap;
  gap: var(--xp-space-4) var(--xp-space-12);
  margin: 0;
  padding: var(--xp-space-4) 0;
  border: 0;
}

.option {
  display: inline-flex;
  align-items: center;
  gap: var(--xp-space-4);
}
</style>
