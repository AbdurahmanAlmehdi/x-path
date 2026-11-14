<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import type { TestRef } from '@/api/client'
import { useProjectsStore } from '@/features/projects/stores/projects'
import { useSessionStore } from '@/features/session/stores/session'
import { useFollowing } from '@/ui/following'
import { formatDuration, formatTime } from '@/ui/format'

import { type KnownTestRun, useTestsStore } from '../stores/tests'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const store = useTestsStore()
const projects = useProjectsStore()

const projectId = computed(() => String(route.params.id))
const jobId = computed(() => {
  const job = Array.isArray(route.query.job) ? route.query.job[0] : route.query.job
  return job || null
})

watch([projectId, jobId], ([project, job]) => void store.open(project, job), { immediate: true })
void projects.load()
useFollowing(store.follow, projects.follow)

const project = computed(() => projects.projects.find((each) => each.id === projectId.value))
const gone = computed(() => projects.loaded && !projects.error && !project.value)
const name = computed(() => project.value?.fullName.split('/').at(-1) ?? projectId.value)
const run = computed(() => store.run?.run)

const subtitle = computed(() =>
  [name.value, run.value?.appPath !== '.' ? run.value?.appPath : undefined, run.value?.branch]
    .filter(Boolean)
    .join(' · '),
)

/** What a run is called in the picker: branch, app, when, baseline. */
function runLabel(known: KnownTestRun): string {
  return [
    known.appPath && known.appPath !== '.' ? known.appPath : undefined,
    known.createdAt ? formatTime(known.createdAt) : known.branch ? 'just ended' : undefined,
    known.baseline ? 'baseline' : undefined,
  ]
    .filter(Boolean)
    .join(' · ')
}

const comparison = computed(() => {
  const shown = run.value
  if (!shown) return ''
  if (shown.baseline) return `This run is the baseline of ${shown.branch}`
  if (!shown.diff.comparedTo) return 'No baseline yet, so every failure counts as new'
  const baseline = store.comparedBaseline
  return baseline
    ? `Compared with the baseline of ${baseline.branch} from ${formatTime(baseline.createdAt)}`
    : `Compared with the baseline run of ${shown.diff.comparedTo}`
})

const newFailures = computed(() => run.value?.diff.newFailures.length ?? 0)

const stats = computed(() => {
  const shown = run.value
  if (!shown) return []
  const { counts, diff } = shown
  return [
    [newFailures.value, 'new failures'],
    [diff.stillFailing, 'in baseline'],
    [diff.fixed.length, 'fixed'],
    [counts.passed, 'passed'],
    [counts.failed, 'failed'],
    [counts.errored, 'errored'],
    [counts.skipped, 'skipped'],
    ...(diff.missing.length > 0 ? [[diff.missing.length, 'missing'] as const] : []),
  ] as Array<readonly [number, string]>
})

const sameTest = (a: TestRef) => (b: TestRef) => a.suite === b.suite && a.name === b.name

interface TestLine {
  ref: TestRef
  label: string
  tone: 'negative' | 'positive' | 'neutral'
  message?: string
}

/** The tests that changed or still fail, new failures first. */
const sections = computed(() => {
  const response = store.run
  if (!response) return []
  const { diff } = response.run
  const failure = (ref: TestRef): TestLine => {
    const test = response.tests.find(sameTest(ref))
    return {
      ref,
      label: test?.status === 'errored' ? 'Errored' : 'Failed',
      tone: 'negative',
      message: test?.message,
    }
  }
  const still = response.tests.filter((test) => !diff.newFailures.some(sameTest(test)))
  return [
    { title: 'New failures', count: diff.newFailures.length, lines: diff.newFailures.map(failure) },
    { title: 'Failing in the baseline too', count: diff.stillFailing, lines: still.map(failure) },
    {
      title: 'Fixed since the baseline',
      count: diff.fixed.length,
      lines: diff.fixed.map((ref): TestLine => ({ ref, label: 'Fixed', tone: 'positive' })),
    },
    {
      title: 'In the baseline, not in this run',
      count: diff.missing.length,
      lines: diff.missing.map((ref): TestLine => ({ ref, label: 'Not reported', tone: 'neutral' })),
    },
  ].filter((section) => section.lines.length > 0)
})

function showRun(job: string) {
  void router.replace({ query: { ...route.query, job } })
}
</script>

<template>
  <section>
    <p v-if="gone" class="notice">This project is no longer on the engine.</p>
    <template v-else>
      <header class="page-header">
        <div>
          <h1 class="xp-type-headline">Tests</h1>
          <p class="muted">
            <RouterLink :to="{ name: 'project', params: { id: projectId } }">{{ subtitle }}</RouterLink>
          </p>
        </div>
        <div class="actions">
          <RouterLink v-if="store.job" :to="{ name: 'job', params: { id: store.job.id } }" class="button">
            Open job
          </RouterLink>
        </div>
      </header>

      <div class="layout" :class="{ picking: store.runs.length > 1 }">
        <nav v-if="store.runs.length > 1" class="picker" aria-label="Test runs">
          <button
            v-for="known in store.runs"
            :key="known.jobId"
            type="button"
            class="pick"
            :class="{ selected: known.jobId === store.shownJobId }"
            @click="showRun(known.jobId)"
          >
            <span class="xp-type-body-strong mono">{{ known.branch ?? known.jobId }}</span>
            <span class="muted">{{ runLabel(known) }}</span>
          </button>
        </nav>

        <div class="shown">
          <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
          <p v-if="store.runError && store.shownJobId" class="alert" role="alert">{{ store.runError }}</p>

          <template v-if="store.run && run">
            <p class="hero xp-type-title" :class="newFailures === 0 ? 'positive' : 'negative'" data-testid="tests-hero">
              {{
                newFailures === 0
                  ? 'No new failures'
                  : newFailures === 1
                    ? '1 new failure'
                    : `${newFailures} new failures`
              }}
            </p>
            <p class="muted meta">
              <span class="mono">{{ run.branch }}</span> · {{ formatTime(run.createdAt) }}
              <template v-if="store.duration !== null"> · <span class="mono">{{ formatDuration(store.duration) }}</span></template>
              · {{ comparison }}
            </p>
            <section class="panel stats">
              <div v-for="[value, label] in stats" :key="label" class="stat">
                <span class="xp-type-code-lg value">{{ value }}</span>
                <span class="muted">{{ label }}</span>
              </div>
            </section>

            <p v-if="store.run.total > store.run.tests.length" class="notice">
              Showing {{ store.run.tests.length }} of {{ store.run.total }} failing tests.
            </p>
            <p v-if="sections.length === 0" class="notice">
              Every test passed and nothing changed against the baseline.
            </p>
            <section v-for="section in sections" :key="section.title" class="panel">
              <h2 class="xp-type-label muted">{{ section.title }} <span class="mono">{{ section.count }}</span></h2>
              <ul class="tests">
                <li v-for="line in section.lines" :key="`${line.ref.suite}/${line.ref.name}`">
                  <div class="test">
                    <span class="xp-type-body-strong name" :title="line.ref.name">{{ line.ref.name }}</span>
                    <span class="mono muted">{{ line.ref.suite }}</span>
                    <span class="label" :class="line.tone">{{ line.label }}</span>
                  </div>
                  <pre v-if="line.message" class="message">{{ line.message.trimEnd() }}</pre>
                </li>
              </ul>
            </section>
          </template>
          <p v-else-if="!store.error && (!store.loaded || (store.shownJobId && !store.runError))" class="muted">
            Loading…
          </p>
          <div v-else-if="store.loaded && store.runs.length === 0" class="empty">
            <p class="xp-type-title">No test runs yet</p>
            <p class="muted">
              Run the Tests workflow. Its runs on the base branch become the baseline that later runs are
              compared with; a run's results also open from its job.
            </p>
            <RouterLink
              v-if="session.can('develop')"
              :to="{ name: 'dispatch', params: { id: projectId }, query: { workflow: 'test' } }"
              class="button primary"
            >
              Run Tests…
            </RouterLink>
          </div>

          <section v-if="store.baselines.length > 0" class="panel" data-testid="baselines">
            <h2 class="xp-type-label muted">Baselines</h2>
            <div class="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th scope="col">App</th>
                    <th scope="col">Branch</th>
                    <th scope="col">passed</th>
                    <th scope="col">failed</th>
                    <th scope="col">skipped</th>
                    <th scope="col">When</th>
                    <th scope="col"><span class="visually-hidden">Run</span></th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="baseline in store.baselines" :key="`${baseline.appPath}/${baseline.branch}`">
                    <td class="mono">{{ baseline.appPath }}</td>
                    <td class="mono">{{ baseline.branch }}</td>
                    <td class="mono">{{ baseline.counts.passed }}</td>
                    <td class="mono">{{ baseline.counts.failed + baseline.counts.errored }}</td>
                    <td class="mono">{{ baseline.counts.skipped }}</td>
                    <td class="muted">{{ formatTime(baseline.createdAt) }}</td>
                    <td>
                      <button
                        type="button"
                        :disabled="baseline.jobId === store.shownJobId"
                        @click="showRun(baseline.jobId)"
                      >
                        Show
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </template>
  </section>
</template>

<style scoped>
.layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: var(--xp-space-16);
}

.layout.picking {
  grid-template-columns: minmax(0, 220px) minmax(0, 1fr);
}

.picker {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-4);
}

.pick {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  height: auto;
  padding: var(--xp-space-6) var(--xp-space-8);
  text-align: left;
  background: transparent;
  border: 0;
}

.pick.selected {
  background: var(--xp-color-surface-selected);
}

.shown {
  min-width: 0;
}

.hero.positive {
  color: var(--xp-color-status-positive-on-container);
}

.hero.negative {
  color: var(--xp-color-status-negative-on-container);
}

.meta {
  overflow-wrap: anywhere;
}

.stats {
  display: flex;
  flex-wrap: wrap;
  gap: var(--xp-space-12) var(--xp-space-24);
}

.stat {
  display: flex;
  flex-direction: column;
}

.tests {
  list-style: none;
  margin: 0;
  padding: 0;
}

.tests li {
  padding: var(--xp-space-6) 0;
  border-top: var(--xp-border-width-hairline) solid var(--xp-color-border-subtle);
}

.test {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--xp-space-4) var(--xp-space-12);
}

.name {
  flex: 1;
  min-width: 0;
  overflow-wrap: anywhere;
}

.label {
  font: var(--xp-type-caption);
}

.label.negative {
  color: var(--xp-color-status-negative-on-container);
}

.label.positive {
  color: var(--xp-color-status-positive-on-container);
}

.message {
  max-height: 9em;
  margin: var(--xp-space-6) 0 0;
  padding: var(--xp-space-6) var(--xp-space-10);
  overflow: auto;
  font: var(--xp-type-code);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  background: var(--xp-color-surface-sunken);
  border-radius: var(--xp-radius-md);
}

.empty {
  margin-top: var(--xp-space-40);
  text-align: center;
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
}

@media (max-width: 760px) {
  .layout.picking {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
