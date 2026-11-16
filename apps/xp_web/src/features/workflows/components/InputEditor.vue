<script setup lang="ts">
import { computed, ref, watch } from 'vue'

import { formatYamlValue, parseYamlValue, type InputType, type WorkflowDocumentInput } from '../document'
import { inputNamePattern } from '../edits'
import BoundField from './BoundField.vue'

/**
 * One input of the workflow, as the Mac app's `InputEditor`: its name, type,
 * whether a dispatch must give it, its description, the options of a
 * choice, and the default of one that is not required (On or Off for a
 * boolean, a menu for a choice, YAML text for the rest). A name the engine
 * does not take, or one another input has, is said and not written: two
 * inputs of one name would be one in the YAML.
 */
const props = defineProps<{
  input: WorkflowDocumentInput
  index: number
  /** The names of the workflow's other inputs. */
  others: string[]
  disabled: boolean
}>()

const emit = defineEmits<{ change: [input: WorkflowDocumentInput]; remove: [] }>()

const types: Array<{ value: InputType | ''; label: string }> = [
  { value: '', label: 'Any' },
  { value: 'string', label: 'Text' },
  { value: 'boolean', label: 'On or off' },
  { value: 'choice', label: 'Choice' },
  { value: 'json', label: 'JSON' },
  { value: 'release', label: 'Release' },
]

// The name as typed: kept while the field has focus, even when it cannot be written.
const name = ref(props.input.name)
const focused = ref(false)
watch(
  () => props.input.name,
  (value) => {
    if (!focused.value) name.value = value
  },
)

const nameProblem = computed(() => {
  const typed = name.value.trim()
  if (!inputNamePattern.test(typed)) return 'Letters, digits and _, starting with a letter or _.'
  return props.others.includes(typed) ? `Another input is called ${typed}.` : null
})

const options = computed(() => props.input.options ?? [])
const defaultKind = computed<'boolean' | 'choice' | 'text'>(() => {
  const value = props.input.defaultValue
  const absent = value === null || value === undefined
  if (props.input.type === 'boolean' && (absent || typeof value === 'boolean')) return 'boolean'
  if (props.input.type === 'choice' && options.value.length > 0 && (absent || typeof value === 'string')) return 'choice'
  return 'text'
})
const choices = computed(() => {
  const value = props.input.defaultValue
  return typeof value === 'string' && !options.value.includes(value) ? [...options.value, value] : options.value
})
const defaultText = computed(() => {
  const value = props.input.defaultValue
  return value === null || value === undefined ? '' : formatYamlValue(value)
})

function change(edit: Partial<WorkflowDocumentInput>) {
  emit('change', { ...props.input, ...edit })
}

function onName(event: Event) {
  name.value = (event.target as HTMLInputElement).value
  if (nameProblem.value === null) change({ name: name.value.trim() })
}

function onNameBlur() {
  focused.value = false
  name.value = props.input.name
}

function onType(event: Event) {
  const value = (event.target as HTMLSelectElement).value
  const type = value === '' ? null : (value as InputType)
  change({ type, options: type === 'choice' ? (props.input.options ?? []) : null })
}

function onRequired(event: Event) {
  const required = (event.target as HTMLInputElement).checked
  change(required ? { required, defaultValue: null } : { required })
}

function onOptions(text: string) {
  change({
    options: text
      .split(',')
      .map((option) => option.trim())
      .filter((option) => option !== ''),
  })
}

function onDefaultPick(event: Event) {
  const value = (event.target as HTMLSelectElement).value
  if (value === '') change({ defaultValue: null })
  else if (defaultKind.value === 'boolean') change({ defaultValue: value === 'true' })
  else change({ defaultValue: value })
}

function onDefaultText(text: string) {
  change({ defaultValue: text.trim() === '' ? null : parseYamlValue(text) })
}
</script>

<template>
  <div class="input-editor" :data-input="index">
    <div class="row">
      <label class="field name">
        <span class="xp-type-label">Input name</span>
        <input
          type="text"
          class="mono"
          :value="name"
          :disabled="disabled"
          autocomplete="off"
          spellcheck="false"
          @focus="focused = true"
          @blur="onNameBlur"
          @input="onName"
        />
      </label>
      <label class="field">
        <span class="xp-type-label">Type</span>
        <select :value="input.type ?? ''" :disabled="disabled" @change="onType">
          <option v-for="type in types" :key="type.value" :value="type.value">{{ type.label }}</option>
        </select>
      </label>
      <label class="check">
        <input type="checkbox" :checked="input.required" :disabled="disabled" @change="onRequired" />
        Required
      </label>
      <button type="button" :disabled="disabled" @click="emit('remove')">Remove input</button>
    </div>
    <p v-if="nameProblem" class="problem" role="alert">{{ nameProblem }}</p>
    <BoundField
      label="Description"
      :value="input.description ?? ''"
      :disabled="disabled"
      @change="(text) => change({ description: text.trim() === '' ? null : text })"
    />
    <BoundField
      v-if="input.type === 'choice'"
      label="Options"
      :value="options.join(', ')"
      placeholder="internal, beta, production"
      :disabled="disabled"
      code
      @change="onOptions"
    />
    <template v-if="!input.required">
      <label v-if="defaultKind !== 'text'" class="field">
        <span class="xp-type-label">Default</span>
        <select
          :class="{ mono: defaultKind === 'choice' }"
          :value="input.defaultValue === null || input.defaultValue === undefined ? '' : String(input.defaultValue)"
          :disabled="disabled"
          @change="onDefaultPick"
        >
          <option value="">None</option>
          <template v-if="defaultKind === 'boolean'">
            <option value="true">On</option>
            <option value="false">Off</option>
          </template>
          <template v-else>
            <option v-for="option in choices" :key="option" :value="option">{{ option }}</option>
          </template>
        </select>
      </label>
      <BoundField
        v-else
        label="Default"
        :value="defaultText"
        placeholder="YAML value"
        :disabled="disabled"
        code
        @change="onDefaultText"
      />
    </template>
  </div>
</template>

<style scoped>
.input-editor {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-8);
  padding: var(--xp-space-12);
  border: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
  border-radius: var(--xp-radius-md);
}

.row {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: var(--xp-space-8) var(--xp-space-12);
}

.name {
  flex: 1;
  min-width: 140px;
}

.check {
  display: inline-flex;
  align-items: center;
  gap: var(--xp-space-6);
  min-height: var(--xp-size-control-md);
}

.problem {
  margin: 0;
  font: var(--xp-type-caption);
  color: var(--xp-color-negative-default);
}
</style>
