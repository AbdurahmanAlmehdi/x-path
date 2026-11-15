<script setup lang="ts">
import type { WorkflowDocument } from '../document'
import { addJob, addStage, newStageName, type WorkflowSelection } from '../edits'

/**
 * The pipeline: the workflow, then its stages in order with their jobs.
 * Picking one shows it in the inspector; Add stage and Add job edit the
 * document and pick what they add.
 */
const props = defineProps<{
  document: WorkflowDocument
  selection: WorkflowSelection
  disabled: boolean
}>()

const emit = defineEmits<{
  select: [selection: WorkflowSelection]
  edit: [document: WorkflowDocument, selection: WorkflowSelection]
}>()

function stepCount(count: number): string {
  if (count === 0) return 'No steps'
  return count === 1 ? '1 step' : `${count} steps`
}

function onAddStage() {
  const stage = props.document.stages.length
  emit('edit', addStage(props.document, newStageName(props.document)), { stage, job: 0 })
}

function onAddJob(stage: number) {
  emit('edit', addJob(props.document, stage), { stage, job: props.document.stages[stage]!.jobs.length })
}
</script>

<template>
  <nav class="graph" aria-label="Pipeline">
    <button
      type="button"
      class="node workflow"
      :aria-pressed="selection.stage === undefined"
      @click="emit('select', {})"
    >
      {{ document.name ?? 'Workflow' }}
    </button>
    <ol class="stages">
      <li v-for="(stage, s) in document.stages" :key="s" class="stage" :data-stage="s">
        <button
          type="button"
          class="node stage-name"
          :aria-pressed="selection.stage === s && selection.job === undefined"
          @click="emit('select', { stage: s })"
        >
          {{ stage.name || `Stage ${s + 1}` }}
        </button>
        <button
          v-for="(job, j) in stage.jobs"
          :key="j"
          type="button"
          class="node job"
          :data-job="job.id"
          :aria-pressed="selection.stage === s && selection.job === j"
          @click="emit('select', { stage: s, job: j })"
        >
          <code>{{ job.id }}</code>
          <span class="muted">{{ stepCount(job.steps.length) }}</span>
        </button>
        <button type="button" class="add" :disabled="disabled" @click="onAddJob(s)">Add job</button>
      </li>
      <li class="stage">
        <button type="button" class="add" :disabled="disabled" @click="onAddStage">Add stage</button>
      </li>
    </ol>
  </nav>
</template>

<style scoped>
.graph {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-12);
  min-width: 0;
}

.stages {
  display: flex;
  gap: var(--xp-space-12);
  margin: 0;
  padding: 0 0 var(--xp-space-4);
  overflow-x: auto;
  list-style: none;
}

.stage {
  display: flex;
  flex: 0 0 180px;
  flex-direction: column;
  gap: var(--xp-space-6);
}

.node {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  height: auto;
  min-height: var(--xp-size-control-md);
  padding: var(--xp-space-6) var(--xp-space-10);
  text-align: left;
  overflow-wrap: anywhere;
}

.workflow {
  align-self: flex-start;
}

.stage-name {
  font: var(--xp-type-label);
  color: var(--xp-color-text-secondary);
}

.node[aria-pressed='true'] {
  border-color: var(--xp-color-accent-default);
  background: var(--xp-color-accent-container);
  color: var(--xp-color-accent-on-container);
}

.add {
  font: var(--xp-type-body);
  color: var(--xp-color-text-secondary);
  border-style: dashed;
}
</style>
