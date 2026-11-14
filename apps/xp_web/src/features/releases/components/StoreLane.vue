<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'

import type { Release, ReleaseStore, RolloutRequest } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'
import Badge from '@/ui/Badge.vue'
import { versionLabel } from '@/ui/format'

import {
  isOver,
  laneSteps,
  liveBefore,
  storeName,
  storeOf,
  storesApproved,
  storeStatus,
} from '../labels'
import { useReleasesStore } from '../stores/releases'

const props = defineProps<{ release: Release; store: ReleaseStore }>()

const router = useRouter()
const session = useSessionStore()
const board = useReleasesStore()

/** The shares of users, in percent, Google Play's staged rollout offers. */
const shares = [5, 10, 20, 50]

/** What the lane asks before it does it: a manual mark, or a new build. */
const confirming = ref<'approved' | 'live' | 'newBuild' | null>(null)

const status = computed(() => storeOf(props.release, props.store))
const manual = computed(() => !board.readsStore(props.release, props.store))
const name = computed(() => storeName(props.store))
const version = computed(() => versionLabel(props.release.version, props.release.build))
const busy = computed(() => board.command !== null)

/** A store the engine cannot read and that has the build: its review is unknown. */
const unknown = computed(
  () => manual.value && (status.value?.state === 'uploaded' || status.value?.state === 'in_review'),
)

const badge = computed(() =>
  !status.value
    ? null
    : unknown.value
      ? { label: 'Unknown', tone: 'neutral' as const }
      : storeStatus(props.store, status.value.state),
)

const steps = computed(() => (status.value ? laneSteps(status.value, manual.value) : []))

const rejectedHere = computed(
  () => status.value?.state === 'rejected' && props.release.state === 'rejected',
)

/** Whether the owner marks the store by hand here: the engine cannot read it, and it has the build. */
const markable = computed(
  () =>
    manual.value &&
    ['uploaded', 'in_review', 'approved'].includes(status.value?.state ?? '') &&
    !isOver(props.release.state) &&
    props.release.state !== 'rejected',
)

const rollsOut = computed(
  () => !manual.value && status.value?.state === 'live' && storesApproved(props.release.state),
)

const before = computed(() =>
  props.release.state === 'rejected' ? undefined : liveBefore(board.releases, props.release, props.store),
)

async function mark(state: 'approved' | 'live') {
  confirming.value = null
  await board.mark(props.store, state)
}

async function newBuild() {
  confirming.value = null
  const run = await board.newBuild()
  if (run) await router.push({ name: 'run', params: { id: run.id } })
}

function rollout(action: RolloutRequest['action'], userFraction?: number) {
  void board.rollout({ store: props.store, action, userFraction })
}

function rollTo(event: Event) {
  const select = event.target as HTMLSelectElement
  const percent = Number(select.value)
  select.value = ''
  if (percent > 0) rollout('fraction', percent / 100)
}
</script>

<template>
  <section class="panel lane" :data-store="store">
    <header class="lane-header">
      <h3 class="xp-type-title">{{ name }}</h3>
      <span class="mono muted">{{ version }}</span>
      <Badge v-if="badge" :status="badge" class="lane-badge" />
    </header>

    <p v-if="!status" class="muted">This release does not go to {{ name }}.</p>
    <template v-else>
      <ol class="steps">
        <li v-for="step in steps" :key="step.label" :class="step.phase">
          <span class="dot" aria-hidden="true" />
          <span class="step-label">{{ step.label }}</span>
          <span v-if="step.time" class="mono muted step-time">{{ step.time }}</span>
        </li>
      </ol>

      <template v-if="rejectedHere">
        <div v-if="confirming === 'newBuild'" class="confirm">
          <p>
            <strong>Build {{ release.version }} again?</strong>
            The production workflow runs again on the release branch with the same version and the next
            free build number; {{ release.build }} is never reused. It asks for your approval like any release.
          </p>
          <div class="actions">
            <button type="button" @click="confirming = null">Cancel</button>
            <button type="button" class="primary" :disabled="busy" @click="newBuild">Start new build</button>
          </div>
        </div>
        <div v-else-if="session.can('develop')" class="actions">
          <button type="button" class="primary" :disabled="busy" @click="confirming = 'newBuild'">
            New build, same version…
          </button>
          <span class="muted">{{ version }} → a new build number</span>
        </div>
      </template>
      <p v-else-if="release.state === 'rejected'" class="muted">
        A new build replaces {{ release.build }} here too, so both stores ship the same build.
      </p>
      <template v-else-if="markable">
        <div v-if="confirming === 'approved' || confirming === 'live'" class="confirm">
          <p>
            <strong>Mark {{ version }} {{ storeStatus(store, confirming).label }}?</strong>
            The engine cannot read this store, so it records your mark as manual, at this time. The release
            moves on from it; a mark cannot be taken back.
          </p>
          <div class="actions">
            <button type="button" @click="confirming = null">Keep</button>
            <button type="button" class="primary" :disabled="busy" @click="mark(confirming)">
              {{ confirming === 'live' ? 'Mark live' : 'Mark approved' }}
            </button>
          </div>
        </div>
        <div v-else-if="session.can('release')" class="actions">
          <button
            v-if="store === 'apple' && status.state !== 'approved'"
            type="button"
            :disabled="busy"
            @click="confirming = 'approved'"
          >
            Mark approved
          </button>
          <button type="button" :disabled="busy" @click="confirming = 'live'">Mark live</button>
        </div>
        <p class="notice">
          {{
            store === 'apple'
              ? 'No App Store Connect API key for this flavor: the engine cannot read the review, and each mark is recorded as manual'
              : 'No Google Play service account for this flavor: the engine cannot read the review, and each mark is recorded as manual'
          }}<template v-if="status.source === 'lookup' && status.detail"> · {{ status.detail }}</template>
        </p>
        <RouterLink
          v-if="session.can('administer')"
          :to="{ name: 'credentials', query: { project: release.projectId } }"
          class="button"
          data-testid="add-credential"
        >
          {{ store === 'apple' ? 'Add API key…' : 'Add service account…' }}
        </RouterLink>
      </template>
      <p v-else-if="!manual && status.note" class="notice">{{ status.note }}</p>

      <template v-if="rollsOut && session.can('develop')">
        <div class="actions" data-testid="rollout">
          <template v-if="store === 'apple'">
            <button type="button" :disabled="busy" @click="rollout('pause')">Pause</button>
            <button type="button" :disabled="busy" @click="rollout('resume')">Resume</button>
          </template>
          <template v-else>
            <select aria-label="Roll out to" :disabled="busy" @change="rollTo">
              <option value="">Roll out to…</option>
              <option v-for="percent in shares" :key="percent" :value="percent">{{ percent }} % of users</option>
            </select>
            <button type="button" :disabled="busy" @click="rollout('halt')">Halt</button>
          </template>
          <button type="button" :disabled="busy" @click="rollout('complete')">Release to all</button>
        </div>
        <p class="muted">Each change waits for your approval.</p>
      </template>

      <p v-if="before" class="muted">
        {{ status.state === 'live' ? `Replaced ${before.version}` : `Live now ${before.version}` }}
      </p>
    </template>
  </section>
</template>

<style scoped>
.lane {
  min-width: 0;
}

.lane-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-8);
  margin-bottom: var(--xp-space-12);
}

.lane-header h3 {
  margin: 0;
}

.lane-badge {
  margin-left: auto;
}

.steps {
  display: grid;
  grid-auto-columns: minmax(0, 1fr);
  grid-auto-flow: column;
  gap: var(--xp-space-8);
  list-style: none;
  margin: 0 0 var(--xp-space-12);
  padding: 0;
}

.steps li {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-2);
  min-width: 0;
  overflow-wrap: anywhere;
}

.dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  border: 2px solid var(--xp-color-border-strong);
}

.done .dot {
  background: var(--xp-color-text-primary);
  border-color: var(--xp-color-text-primary);
}

.now .dot {
  border-width: 3px;
  border-color: var(--xp-color-accent-default);
}

.now .step-label {
  font: var(--xp-type-body-strong);
}

.todo .step-label {
  color: var(--xp-color-text-secondary);
}

.step-time {
  font: var(--xp-type-caption);
}

.confirm {
  margin-bottom: var(--xp-space-8);
}

.lane .actions + p,
.lane .notice {
  margin-top: var(--xp-space-8);
}
</style>
