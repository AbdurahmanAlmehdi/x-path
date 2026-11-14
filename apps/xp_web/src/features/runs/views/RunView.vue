<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import type { RunJob } from '@/api/client'
import { useProjectsStore } from '@/features/projects/stores/projects'
import { useWorkflowsStore } from '@/features/projects/stores/workflows'
import { useSessionStore } from '@/features/session/stores/session'
import { useFollowing } from '@/ui/following'
import { formatTime, originOf, scopeOf, versionLabel } from '@/ui/format'
import StatusBadge from '@/ui/StatusBadge.vue'

import { useRunStore } from '../stores/run'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const store = useRunStore()
const workflows = useWorkflowsStore()
const projects = useProjectsStore()

/** Whether the page asks before it cancels. */
const confirming = ref(false)

watch(
  () => String(route.params.id),
  async (id) => {
    confirming.value = false
    await store.open(id)
    if (store.run) void workflows.know([store.run.projectId])
  },
  { immediate: true },
)
void projects.load()
useFollowing(store.follow, workflows.follow)

const title = computed(() => (store.run ? workflows.name(store.run.workflowId) : 'Run'))
const projectName = computed(
  () =>
    projects.projects.find((project) => project.id === store.run?.projectId)?.fullName ??
    store.run?.projectId,
)

/** The jobs of the run by stage, in order. */
const stages = computed(() => {
  const byStage = new Map<number, RunJob[]>()
  for (const job of store.run?.jobs ?? []) {
    byStage.set(job.stage, [...(byStage.get(job.stage) ?? []), job])
  }
  return [...byStage.entries()].sort(([a], [b]) => a - b)
})

async function cancel() {
  confirming.value = false
  await store.act('cancel')
}

async function runAgain() {
  const run = await store.act('runAgain')
  if (run && run.id !== store.id) await router.push({ name: 'run', params: { id: run.id } })
}
</script>

<template>
  <section>
    <p v-if="store.missing" class="notice">This run is not on the engine.</p>
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <template v-if="store.run">
      <header class="page-header">
        <div>
          <h1 class="xp-type-headline">{{ title }}</h1>
          <StatusBadge :state="store.run.state" />
        </div>
        <div v-if="session.can('develop')" class="actions">
          <template v-if="confirming">
            <span>Cancel {{ title }}? Jobs that have not started will not run.</span>
            <button type="button" class="danger" :disabled="store.busy !== null" @click="cancel">
              Cancel run
            </button>
            <button type="button" @click="confirming = false">Keep running</button>
          </template>
          <template v-else>
            <button v-if="store.rerunnable" type="button" :disabled="store.busy !== null" @click="store.act('rerunFailed')">
              Re-run failed jobs
            </button>
            <button type="button" :disabled="store.busy !== null" @click="runAgain">Run again</button>
            <button v-if="store.cancellable" type="button" :disabled="store.busy !== null" @click="confirming = true">
              Cancel
            </button>
          </template>
        </div>
      </header>

      <section class="panel">
        <dl class="facts">
          <dt>Project</dt>
          <dd>
            <RouterLink :to="{ name: 'project', params: { id: store.run.projectId } }">{{ projectName }}</RouterLink>
          </dd>
          <template v-if="store.run.version">
            <dt>Version</dt>
            <dd class="mono">{{ versionLabel(store.run.version, store.run.build) }}</dd>
          </template>
          <template v-if="scopeOf(store.run)">
            <dt>For</dt>
            <dd class="mono">{{ scopeOf(store.run) }}</dd>
          </template>
          <dt>Commit</dt>
          <dd class="mono">
            <template v-if="store.run.ref">{{ store.run.ref }} · </template>{{ store.run.sha.slice(0, 12) }}
          </dd>
          <template v-if="originOf(store.run)">
            <dt>Started by</dt>
            <dd data-testid="run-origin">{{ originOf(store.run) }}</dd>
          </template>
          <dt>Dispatched</dt>
          <dd>{{ formatTime(store.run.createdAt) }}</dd>
        </dl>
      </section>

      <section class="panel">
        <h2 class="xp-type-title">Jobs</h2>
        <div v-for="[stage, jobs] in stages" :key="stage" class="stage">
          <h3 class="xp-type-label muted">Stage {{ stage + 1 }}</h3>
          <ul class="jobs">
            <li v-for="job in jobs" :key="job.id">
              <RouterLink :to="{ name: 'job', params: { id: job.id } }" class="job">
                <StatusBadge :state="job.state" />
                <span class="xp-type-body-strong">{{ job.name }}</span>
                <span v-if="job.message" class="muted message">{{ job.message }}</span>
              </RouterLink>
            </li>
          </ul>
        </div>
      </section>
    </template>
    <p v-else-if="!store.missing && !store.error" class="muted">Loading…</p>
  </section>
</template>

<style scoped>
.page-header h1 {
  margin-bottom: var(--xp-space-4);
}

.stage + .stage {
  margin-top: var(--xp-space-12);
}

.stage h3 {
  margin: 0 0 var(--xp-space-4);
}

.jobs {
  list-style: none;
  margin: 0;
  padding: 0;
}

.job {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-4) var(--xp-space-12);
  min-height: var(--xp-size-row-default);
  padding: var(--xp-space-6) var(--xp-space-8);
  color: var(--xp-color-text-primary);
  text-decoration: none;
  border-radius: var(--xp-radius-md);
}

.job:hover {
  background: var(--xp-color-surface-hover);
}

.message {
  flex-basis: 100%;
  overflow-wrap: anywhere;
}
</style>
