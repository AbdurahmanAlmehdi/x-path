<script setup lang="ts">
import { computed } from 'vue'

import type { StepKeySchema, WorkflowSchema } from '@/api/client'

import type { WorkflowStep } from '../document'
import { withValue } from '../edits'
import { gateLabel } from '../labels'
import BoundField from './BoundField.vue'
import WithField from './WithField.vue'

/**
 * One step of a job: a row with its type and gate that opens to edit them,
 * its `if` and its `with` values, the keys the engine's schema gives the
 * type first.
 */
const props = defineProps<{
  step: WorkflowStep
  index: number
  count: number
  schema: WorkflowSchema | null
  disabled: boolean
}>()

const emit = defineEmits<{ change: [step: WorkflowStep]; move: [delta: number]; remove: [] }>()

const known = computed(() => props.schema?.steps.find((each) => each.kind === props.step.kind))
const typed = computed(() => new Map<string, StepKeySchema>((known.value?.keys ?? []).map((key) => [key.name, key])))
const keys = computed(() => [
  ...new Set([...(known.value?.with ?? []), ...typed.value.keys(), ...Object.keys(props.step.with)]),
])
const kinds = computed(() => {
  const groups = new Map<string, string[]>()
  for (const type of props.schema?.steps ?? []) groups.set(type.group, [...(groups.get(type.group) ?? []), type.kind])
  const knownKind = props.schema?.steps.some((type) => type.kind === props.step.kind)
  if (!knownKind) groups.set('Other', [...(groups.get('Other') ?? []), props.step.kind])
  return [...groups.entries()]
})
const gates = computed(() => [
  ...new Set([...(props.schema?.gates ?? []), ...(props.step.gate ? [props.step.gate] : [])]),
])

function change(fields: Partial<WorkflowStep>) {
  emit('change', { ...props.step, ...fields })
}

function orNull(text: string): string | null {
  return text.trim() === '' ? null : text
}
</script>

<template>
  <details class="step" :data-step="index">
    <summary>
      <span class="number muted">{{ index + 1 }}</span>
      <code class="kind">{{ step.kind || '(no type)' }}</code>
      <span v-if="step.gate" class="gate xp-type-label">{{ gateLabel(step.gate, schema) }}</span>
      <span v-if="step.condition" class="muted mono condition">if {{ step.condition }}</span>
    </summary>
    <div class="fields">
      <div class="row">
        <label v-if="schema" class="field">
          <span class="xp-type-label">Step type</span>
          <select
            class="mono"
            :value="step.kind"
            :disabled="disabled"
            @change="change({ kind: ($event.target as HTMLSelectElement).value })"
          >
            <optgroup v-for="[group, members] in kinds" :key="group" :label="group">
              <option v-for="kind in members" :key="kind" :value="kind">{{ kind }}</option>
            </optgroup>
          </select>
        </label>
        <BoundField
          v-else
          label="Step type"
          :value="step.kind"
          :disabled="disabled"
          code
          @change="(text) => change({ kind: text.trim() })"
        />
        <label class="field">
          <span class="xp-type-label">Gate</span>
          <select
            :value="step.gate ?? ''"
            :disabled="disabled"
            @change="change({ gate: orNull(($event.target as HTMLSelectElement).value) })"
          >
            <option value="">No gate</option>
            <option v-for="gate in gates" :key="gate" :value="gate">{{ gateLabel(gate, schema) }}</option>
          </select>
        </label>
      </div>
      <BoundField
        label="If"
        :value="step.condition ?? ''"
        placeholder="platform == 'ios'"
        :disabled="disabled"
        code
        @change="(text) => change({ condition: orNull(text) })"
      />
      <p v-if="known" class="muted">{{ known.description }}</p>
      <template v-if="keys.length > 0">
        <span class="xp-type-label muted">With</span>
        <WithField
          v-for="key in keys"
          :key="key"
          :name="key"
          :key-schema="typed.get(key)"
          :given="key in step.with"
          :value="step.with[key]"
          :disabled="disabled"
          @change="(value) => change({ with: withValue(step.with, key, value) })"
        />
      </template>
      <div class="actions">
        <button type="button" :disabled="disabled || index === 0" @click="emit('move', -1)">Move earlier</button>
        <button type="button" :disabled="disabled || index === count - 1" @click="emit('move', 1)">Move later</button>
        <button type="button" :disabled="disabled" @click="emit('remove')">Remove step</button>
      </div>
    </div>
  </details>
</template>

<style scoped>
.step {
  border: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
  border-radius: var(--xp-radius-md);
  background: var(--xp-color-surface-raised);
}

summary {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--xp-space-8);
  padding: var(--xp-space-6) var(--xp-space-10);
  cursor: pointer;
}

.kind,
.condition {
  overflow-wrap: anywhere;
}

.gate {
  color: var(--xp-color-warning-default);
}

.fields {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-10);
  padding: var(--xp-space-8) var(--xp-space-10) var(--xp-space-10);
  border-top: var(--xp-border-width-hairline) solid var(--xp-color-border-subtle);
}

.row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: var(--xp-space-10);
}

.fields :deep(input),
.fields select {
  width: 100%;
}
</style>
