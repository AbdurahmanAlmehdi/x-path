<script setup lang="ts">
import { computed, onBeforeUnmount, watch } from 'vue'
import { useRoute } from 'vue-router'

import type { JobStep } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'
import { useFollowing } from '@/ui/following'
import { formatDuration, statusOf, stepKind } from '@/ui/format'
import StatusBadge from '@/ui/StatusBadge.vue'

import LogView from '../components/LogView.vue'
import { useJobStore } from '../stores/job'
import { useJobLogStore } from '../stores/log'

const route = useRoute()
const session = useSessionStore()
const store = useJobStore()
const log = useJobLogStore()

watch(
  () => String(route.params.id),
  (id) => {
    void store.open(id)
    log.follow(id)
  },
  { immediate: true },
)
useFollowing(store.follow)
onBeforeUnmount(() => log.stop())

// A job resumed after its log ended writes on: follow it again, from the
// line after the last one held.
watch(
  () => store.job?.state,
  (state) => {
    const id = store.id
    if (id && log.ended !== null && (state === 'queued' || state === 'running')) log.follow(id)
  },
)

/** What happened to the job, said without hovering. */
const band = computed(() => {
  const job = store.job
  if (!job) return null
  if (job.state === 'waiting_for_resume') {
    const step = job.steps.find((each) => each.state === 'interrupted')
    return `The engine stopped during ${step ? stepKind(step.kind) : 'a step'}, which changes something outside the engine, so it never runs again by itself. Check, then resume.`
  }
  if (job.state === 'interrupted') {
    return 'The engine stopped while this job ran. Finished steps are kept; resume runs the interrupted step again from its start.'
  }
  if (job.state === 'failed' || job.state === 'cancelled') return job.message ?? null
  if (job.state === 'queued' && job.message) return `Waiting: ${job.message}`
  return null
})

function took(step: JobStep): string | null {
  if (!step.startedAt) return null
  const end = step.finishedAt ? Date.parse(step.finishedAt) : Date.now()
  return formatDuration(end - Date.parse(step.startedAt))
}
</script>

<template>
  <section>
    <p v-if="store.missing" class="notice">This job is not on the engine.</p>
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <template v-if="store.job">
      <header class="page-header">
        <div>
          <p v-if="store.job.runId" class="muted">
            <RouterLink :to="{ name: 'run', params: { id: store.job.runId } }">Back to the run</RouterLink>
          </p>
          <h1 class="xp-type-headline">{{ store.job.name ?? 'Job' }}</h1>
          <StatusBadge :state="store.job.state" />
        </div>
        <div v-if="session.can('develop')" class="actions">
          <button v-if="store.resumable" type="button" :disabled="store.busy !== null" @click="store.act('resume')">
            Resume
          </button>
          <button v-if="store.cancellable" type="button" :disabled="store.busy !== null" @click="store.act('cancel')">
            Cancel
          </button>
        </div>
      </header>
      <p v-if="band" class="notice" data-testid="job-band">{{ band }}</p>

      <section class="panel">
        <h2 class="xp-type-title">Steps</h2>
        <ol class="steps">
          <li v-for="step in store.job.steps" :key="step.ordinal" class="step">
            <StatusBadge :state="step.state" />
            <span class="xp-type-body-strong">{{ stepKind(step.kind) }}</span>
            <span v-if="took(step)" class="muted">{{ took(step) }}</span>
            <span v-if="step.message" class="muted message">{{ step.message }}</span>
          </li>
        </ol>
      </section>

      <section class="panel">
        <h2 class="xp-type-title">Log</h2>
        <LogView />
        <p v-if="log.ended" class="muted ended">The log ended: {{ statusOf(log.ended).label }}.</p>
      </section>
    </template>
    <p v-else-if="!store.missing && !store.error" class="muted">Loading…</p>
  </section>
</template>

<style scoped>
.page-header h1 {
  margin-bottom: var(--xp-space-4);
}

.steps {
  list-style: none;
  margin: 0;
  padding: 0;
}

.step {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-4) var(--xp-space-12);
  min-height: var(--xp-size-row-compact);
  padding: var(--xp-space-4) 0;
}

.message {
  flex-basis: 100%;
  overflow-wrap: anywhere;
}

.ended {
  margin: var(--xp-space-6) 0 0;
}
</style>
