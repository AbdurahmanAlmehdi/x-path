<script setup lang="ts">
import { computed } from 'vue'

import type { WorkflowSchema } from '@/api/client'

import type { WorkflowDocument, WorkflowJob, WorkflowMatrixAxis } from '../document'
import {
  addStep,
  editJob,
  editStage,
  editStep,
  moveJob,
  moveStage,
  moveStep,
  removeJob,
  removeStage,
  removeStep,
  withAxis,
  type WorkflowSelection,
} from '../edits'
import { fallbackAxes, fallbackPlatforms } from '../labels'
import BoundField from './BoundField.vue'
import StepEditor from './StepEditor.vue'

/**
 * The fields of what the pipeline has selected: the workflow (name,
 * description, lock), a stage (its name and place), or a job (id, name,
 * `if`, matrix, capabilities and its steps with type, gate, `if` and `with`).
 * The workflow's inputs are edited in the YAML.
 */
const props = defineProps<{
  document: WorkflowDocument
  selection: WorkflowSelection
  schema: WorkflowSchema | null
  disabled: boolean
}>()

const emit = defineEmits<{ edit: [document: WorkflowDocument, selection?: WorkflowSelection] }>()

const stage = computed(() => (props.selection.stage === undefined ? null : props.selection.stage))
const job = computed<WorkflowJob | null>(() => {
  const { stage: s, job: j } = props.selection
  return s === undefined || j === undefined ? null : (props.document.stages[s]?.jobs[j] ?? null)
})
const axes = computed(() => [
  ...new Set([...(props.schema?.matrixAxes ?? fallbackAxes), ...(job.value?.matrix.map((axis) => axis.name) ?? [])]),
])
const capabilities = computed(() => [
  ...new Set([...(props.schema?.capabilities ?? []), ...(job.value?.capabilities ?? [])]),
])
const stepGroups = computed(() => {
  const groups = new Map<string, Array<{ kind: string; title: string }>>()
  for (const type of props.schema?.steps ?? []) {
    groups.set(type.group, [...(groups.get(type.group) ?? []), { kind: type.kind, title: type.title }])
  }
  return [...groups.entries()]
})

function orNull(text: string): string | null {
  return text.trim() === '' ? null : text
}

function onJob(edit: (job: WorkflowJob) => WorkflowJob, selection?: WorkflowSelection) {
  const { stage: s, job: j } = props.selection
  emit('edit', editJob(props.document, s!, j!, edit), selection)
}

type AxisMode = 'none' | 'dispatch' | 'list'

function modeOf(axis: WorkflowMatrixAxis | undefined): AxisMode {
  if (!axis) return 'none'
  return axis.values === null ? 'dispatch' : 'list'
}

function axisOf(name: string): WorkflowMatrixAxis | undefined {
  return job.value?.matrix.find((axis) => axis.name === name)
}

function onAxisMode(name: string, mode: AxisMode) {
  const platforms = props.schema?.platforms ?? fallbackPlatforms
  const axis: WorkflowMatrixAxis | null =
    mode === 'none'
      ? null
      : mode === 'dispatch'
        ? { name, values: null, reference: `\${{ ${name}s }}` }
        : { name, values: name === 'platform' ? [...platforms] : [], reference: null }
  onJob((j) => withAxis(j, name, axis))
}

function onAxisValues(name: string, text: string) {
  const values = text
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value !== '')
  onJob((j) => withAxis(j, name, { name, values, reference: null }))
}

function onCapability(capability: string, on: boolean) {
  onJob((j) => ({
    ...j,
    capabilities: on ? [...j.capabilities, capability] : j.capabilities.filter((each) => each !== capability),
  }))
}

function onAddStep(event: Event) {
  const select = event.target as HTMLSelectElement
  const kind = select.value
  select.value = ''
  if (kind !== '') onJob((j) => addStep(j, kind))
}
</script>

<template>
  <section class="panel inspector" aria-label="Inspector">
    <!-- A job of a stage. -->
    <div v-if="job && stage !== null" class="form" data-testid="job-fields">
      <header class="head">
        <span class="xp-type-label muted">Stage {{ stage + 1 }} · Job</span>
        <div class="actions">
          <button
            type="button"
            :disabled="disabled || selection.job === 0"
            @click="emit('edit', moveJob(document, stage, selection.job!, -1), { stage, job: selection.job! - 1 })"
          >
            Move earlier
          </button>
          <button
            type="button"
            :disabled="disabled || selection.job === document.stages[stage]!.jobs.length - 1"
            @click="emit('edit', moveJob(document, stage, selection.job!, 1), { stage, job: selection.job! + 1 })"
          >
            Move later
          </button>
          <button
            type="button"
            :disabled="disabled"
            @click="emit('edit', removeJob(document, stage, selection.job!), { stage })"
          >
            Remove job
          </button>
        </div>
      </header>
      <div class="row">
        <BoundField
          label="Job id"
          :value="job.id"
          :disabled="disabled"
          code
          @change="(text) => onJob((j) => ({ ...j, id: text.trim() }))"
        />
        <BoundField
          label="Job name"
          :value="job.name ?? ''"
          placeholder="The id with the matrix values by default"
          :disabled="disabled"
          @change="(text) => onJob((j) => ({ ...j, name: orNull(text) }))"
        />
      </div>
      <BoundField
        label="If"
        :value="job.condition ?? ''"
        placeholder="platform == 'ios'"
        :disabled="disabled"
        code
        @change="(text) => onJob((j) => ({ ...j, condition: orNull(text) }))"
      />

      <fieldset class="group">
        <legend class="xp-type-label muted">Matrix</legend>
        <div v-for="name in axes" :key="name" class="axis" :data-axis="name">
          <code class="axis-name">{{ name }}</code>
          <select
            :aria-label="`Matrix ${name}`"
            :value="modeOf(axisOf(name))"
            :disabled="disabled"
            @change="onAxisMode(name, ($event.target as HTMLSelectElement).value as AxisMode)"
          >
            <option value="none">None</option>
            <option value="dispatch">From dispatch</option>
            <option value="list">Listed</option>
          </select>
          <code v-if="modeOf(axisOf(name)) === 'dispatch'" class="muted">{{ axisOf(name)!.reference }}</code>
          <BoundField
            v-else-if="modeOf(axisOf(name)) === 'list'"
            class="axis-values"
            :label="`${name} values`"
            :value="axisOf(name)!.values!.join(', ')"
            placeholder="prod, dev"
            :disabled="disabled"
            code
            @change="(text) => onAxisValues(name, text)"
          />
        </div>
      </fieldset>

      <fieldset v-if="capabilities.length > 0" class="group">
        <legend class="xp-type-label muted">Capabilities</legend>
        <div class="checks">
          <label v-for="capability in capabilities" :key="capability" class="check">
            <input
              type="checkbox"
              :checked="job.capabilities.includes(capability)"
              :disabled="disabled"
              @change="onCapability(capability, ($event.target as HTMLInputElement).checked)"
            />
            <code>{{ capability }}</code>
          </label>
        </div>
      </fieldset>

      <div class="steps-head">
        <span class="xp-type-label muted">Steps</span>
        <select
          v-if="schema"
          aria-label="Add step"
          class="add-step"
          :disabled="disabled"
          value=""
          @change="onAddStep"
        >
          <option value="" disabled>Add step…</option>
          <optgroup v-for="[group, types] in stepGroups" :key="group" :label="group">
            <option v-for="type in types" :key="type.kind" :value="type.kind">{{ type.kind }} — {{ type.title }}</option>
          </optgroup>
        </select>
      </div>
      <p v-if="!schema" class="muted">
        The engine cannot be reached, so its step types are not known. Edit the YAML for now, or try again once it
        answers.
      </p>
      <p v-if="job.steps.length === 0" class="muted">No steps</p>
      <StepEditor
        v-for="(step, index) in job.steps"
        :key="index"
        :step="step"
        :index="index"
        :count="job.steps.length"
        :schema="schema"
        :disabled="disabled"
        @change="(next) => onJob((j) => editStep(j, index, () => next))"
        @move="(delta) => onJob((j) => moveStep(j, index, delta))"
        @remove="onJob((j) => removeStep(j, index))"
      />
    </div>

    <!-- A stage. -->
    <div v-else-if="stage !== null" class="form" data-testid="stage-fields">
      <header class="head">
        <span class="xp-type-label muted">Stage {{ stage + 1 }}</span>
        <div class="actions">
          <button
            type="button"
            :disabled="disabled || stage === 0"
            @click="emit('edit', moveStage(document, stage, -1), { stage: stage - 1 })"
          >
            Move earlier
          </button>
          <button
            type="button"
            :disabled="disabled || stage === document.stages.length - 1"
            @click="emit('edit', moveStage(document, stage, 1), { stage: stage + 1 })"
          >
            Move later
          </button>
          <button type="button" :disabled="disabled" @click="emit('edit', removeStage(document, stage), {})">
            Remove stage
          </button>
        </div>
      </header>
      <BoundField
        label="Stage name"
        :value="document.stages[stage]!.name"
        :disabled="disabled"
        @change="(text) => emit('edit', editStage(document, stage!, (s) => ({ ...s, name: text })))"
      />
      <p class="muted">Select a job in the pipeline to edit its matrix and steps.</p>
    </div>

    <!-- The workflow itself. -->
    <div v-else class="form" data-testid="workflow-fields">
      <BoundField
        label="Name"
        :value="document.name ?? ''"
        :disabled="disabled"
        @change="(text) => emit('edit', { ...document, name: orNull(text) })"
      />
      <BoundField
        label="Description"
        :value="document.description ?? ''"
        :disabled="disabled"
        multiline
        @change="(text) => emit('edit', { ...document, description: orNull(text) })"
      />
      <label class="check">
        <input
          type="checkbox"
          :checked="document.locksProject"
          :disabled="disabled"
          @change="emit('edit', { ...document, locksProject: ($event.target as HTMLInputElement).checked })"
        />
        One run at a time per project
      </label>
      <p class="muted">It also makes the production flavors the default when a dispatch names none.</p>
      <div>
        <span class="xp-type-label muted">Inputs</span>
        <p v-if="document.inputs.length === 0" class="muted">No inputs</p>
        <ul v-else class="inputs">
          <li v-for="input in document.inputs" :key="input.name">
            <code>{{ input.name }}</code>
            <span v-if="input.description" class="muted"> — {{ input.description }}</span>
          </li>
        </ul>
        <p class="muted">A dispatch sets them; the steps read them as inputs.&lt;name&gt;. Edit them in the YAML.</p>
      </div>
    </div>
  </section>
</template>

<style scoped>
.inspector {
  min-width: 0;
}

.head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--xp-space-8);
}

.row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: var(--xp-space-10);
}

.form :deep(input[type='text']),
.form :deep(textarea) {
  width: 100%;
}

.group {
  margin: 0;
  padding: 0;
  border: 0;
}

.axis {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-8);
  margin-top: var(--xp-space-6);
}

.axis-name {
  width: 72px;
}

.axis-values {
  flex: 1;
  min-width: 140px;
}

.axis-values :deep(.xp-type-label) {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
}

.checks {
  display: flex;
  flex-wrap: wrap;
  gap: var(--xp-space-4) var(--xp-space-12);
  margin-top: var(--xp-space-6);
}

.check {
  display: inline-flex;
  align-items: center;
  gap: var(--xp-space-6);
}

.steps-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--xp-space-8);
}

.add-step {
  max-width: 100%;
}

.inputs {
  margin: var(--xp-space-4) 0;
  padding-left: var(--xp-space-16);
}
</style>
