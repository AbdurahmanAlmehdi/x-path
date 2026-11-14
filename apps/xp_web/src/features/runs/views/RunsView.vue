<script setup lang="ts">
import { computed, onMounted, watch } from 'vue'
import { type LocationQueryValue, useRoute, useRouter } from 'vue-router'

import type { RunState } from '@/api/client'
import { useProjectsStore } from '@/features/projects/stores/projects'
import { useWorkflowsStore } from '@/features/projects/stores/workflows'
import { useFollowing } from '@/ui/following'
import { runStates, statusOf } from '@/ui/format'

import RunList from '../components/RunList.vue'
import { type RunsFilter, useRunsStore } from '../stores/runs'

const route = useRoute()
const router = useRouter()
const runs = useRunsStore()
const projects = useProjectsStore()
const workflows = useWorkflowsStore()

function one(value: LocationQueryValue | LocationQueryValue[] | undefined): string | undefined {
  const first = Array.isArray(value) ? value[0] : value
  return first || undefined
}

/** The project of `/projects/:id/runs`; the global page has none. */
const fixedProject = computed(() =>
  route.params.id === undefined ? undefined : String(route.params.id),
)

/** The filters, from the address: it can be shared and reloaded. */
const filter = computed<RunsFilter>(() => {
  const state = one(route.query.state)
  return {
    project: fixedProject.value ?? one(route.query.project),
    workflow: one(route.query.workflow),
    state: runStates.includes(state as RunState) ? (state as RunState) : undefined,
  }
})

const project = computed(() => projects.projects.find((each) => each.id === filter.value.project))
const projectWorkflows = computed(() =>
  filter.value.project ? (workflows.byProject[filter.value.project] ?? []) : [],
)

watch(
  filter,
  (wanted) => {
    void runs.load(wanted)
    if (wanted.project) void workflows.know([wanted.project])
  },
  { immediate: true },
)
onMounted(() => projects.load())
useFollowing(runs.follow, workflows.follow)

/** Shows the runs filtered by [changes]; a project change drops the workflow, which is the project's. */
function refine(changes: Partial<Record<'project' | 'workflow' | 'state', string>>) {
  const query: Record<string, unknown> = { ...route.query, ...changes }
  if ('project' in changes) delete query.workflow
  for (const [name, value] of Object.entries(query)) if (!value) delete query[name]
  void router.replace({ query: query as typeof route.query })
}

function selected(event: Event): string {
  return (event.target as HTMLSelectElement).value
}
</script>

<template>
  <section>
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Runs</h1>
        <p v-if="fixedProject" class="muted">
          <RouterLink :to="{ name: 'project', params: { id: fixedProject } }">
            {{ project?.fullName ?? fixedProject }}
          </RouterLink>
        </p>
      </div>
      <div class="actions filters">
        <label v-if="!fixedProject">
          <span class="xp-type-label">Project</span>
          <select :value="filter.project ?? ''" @change="refine({ project: selected($event) })">
            <option value="">All projects</option>
            <option v-for="each in projects.projects" :key="each.id" :value="each.id">
              {{ each.fullName }}
            </option>
          </select>
        </label>
        <label v-if="filter.project">
          <span class="xp-type-label">Workflow</span>
          <select :value="filter.workflow ?? ''" @change="refine({ workflow: selected($event) })">
            <option value="">All workflows</option>
            <option v-for="each in projectWorkflows" :key="each.id" :value="each.id">
              {{ each.title ?? each.name }}
            </option>
          </select>
        </label>
        <label>
          <span class="xp-type-label">State</span>
          <select :value="filter.state ?? ''" @change="refine({ state: selected($event) })">
            <option value="">All states</option>
            <option v-for="state in runStates" :key="state" :value="state">
              {{ statusOf(state).label }}
            </option>
          </select>
        </label>
      </div>
    </header>
    <p v-if="runs.error" class="alert" role="alert">{{ runs.error }}</p>
    <div class="panel">
      <p v-if="!runs.loaded" class="muted">Loading…</p>
      <RunList
        v-else
        :runs="runs.runs"
        :show-project="!filter.project"
        :empty="filter.workflow || filter.state ? 'No run matches.' : 'Nothing has run yet. Dispatch a workflow to see its runs here.'"
      />
      <button v-if="runs.next" type="button" class="more" :disabled="runs.loadingMore" @click="runs.more()">
        {{ runs.loadingMore ? 'Loading…' : 'Show older runs' }}
      </button>
    </div>
  </section>
</template>

<style scoped>
.filters label {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-2);
  max-width: 100%;
}

/* A long project name does not widen the page. */
.filters select {
  width: 100%;
  max-width: 24rem;
}

.filters span {
  color: var(--xp-color-text-tertiary);
}

.more {
  margin-top: var(--xp-space-8);
}
</style>
