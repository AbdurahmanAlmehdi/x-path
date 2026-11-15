<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'

import type { Runner } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'
import Badge from '@/ui/Badge.vue'
import Dialog from '@/ui/Dialog.vue'
import { useFollowing } from '@/ui/following'
import { formatTime, timeAgo } from '@/ui/format'

import PairRunnerDialog from '../components/PairRunnerDialog.vue'
import { runnerMachine, runnerStatus } from '../labels'
import { useRunnersStore } from '../stores/runners'

const session = useSessionStore()
const store = useRunnersStore()

onMounted(() => store.load())
useFollowing(store.follow)

const pairing = ref(false)
/** The runner whose revoke is being confirmed. */
const revoking = ref<Runner | null>(null)

const subtitle = computed(() => {
  const count = store.active.length
  return `${count === 1 ? '1 runner' : `${count} runners`} · ${store.busy} busy`
})

function jobsLine(count: number): string {
  return count === 1
    ? 'The job it holds is queued again, or waits for a resume if it had a step with side effects.'
    : `The ${count} jobs it holds are queued again, or wait for a resume if they had a step with side effects.`
}

async function revoke(runner: Runner) {
  if (await store.revoke(runner.id)) revoking.value = null
}
</script>

<template>
  <section>
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Runners</h1>
        <p v-if="store.loaded" class="muted">{{ subtitle }}</p>
      </div>
      <div class="actions">
        <button v-if="session.can('administer')" type="button" class="primary" @click="pairing = true">
          Pair runner…
        </button>
      </div>
    </header>
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <p v-if="!store.loaded" class="muted">Loading…</p>
    <div v-else-if="store.active.length === 0" class="panel">
      <h2 class="xp-type-title">No runners yet</h2>
      <p class="muted">Pair a Mac or a Linux machine and the engine sends it the jobs that fit its capabilities.</p>
    </div>
    <div v-else class="panel table-wrap">
      <table data-testid="runners">
        <thead>
          <tr>
            <th>Runner</th>
            <th>Status</th>
            <th>Capabilities</th>
            <th>Slots</th>
            <th>Last heard</th>
            <th v-if="session.can('administer')"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="runner in store.active" :key="runner.id">
            <td>
              <span class="xp-type-body-strong">{{ runner.name }}</span>
              <span class="muted block">{{ runnerMachine(runner) }}</span>
            </td>
            <td><Badge :status="runnerStatus(runner)" /></td>
            <td>
              <span v-if="runner.capabilities.length === 0 && !runner.missing?.length" class="muted">
                Not probed yet
              </span>
              <code v-else>{{ runner.capabilities.join(' · ') }}</code>
              <span v-for="missing in runner.missing ?? []" :key="missing.capability" class="muted block">
                No {{ missing.capability }}: {{ missing.reason }}. {{ missing.fix }}.
              </span>
            </td>
            <td class="mono">{{ runner.jobIds.length }}/{{ runner.slots }}</td>
            <td>
              <span v-if="runner.lastHeartbeat" :title="formatTime(runner.lastHeartbeat)">
                {{ timeAgo(runner.lastHeartbeat) }}
              </span>
              <span v-else class="muted">Never</span>
            </td>
            <td v-if="session.can('administer')">
              <button type="button" @click="revoking = runner">Revoke…</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="store.revoked.length > 0" class="panel">
      <h2 class="xp-type-title">Revoked</h2>
      <ul class="revoked">
        <li v-for="runner in store.revoked" :key="runner.id">
          <span>{{ runner.name }}</span>
          <span v-if="runner.revokedAt" class="muted"> · Revoked {{ timeAgo(runner.revokedAt) }}</span>
        </li>
      </ul>
    </div>

    <PairRunnerDialog v-if="pairing" @close="pairing = false; store.load()" />
    <Dialog v-if="revoking" :title="`Revoke ${revoking.name}?`" @close="revoking = null">
      <ul class="consequences">
        <li>Its credential stops working and its connection closes.</li>
        <li v-if="revoking.jobIds.length > 0">{{ jobsLine(revoking.jobIds.length) }}</li>
        <li>The name {{ revoking.name }} stays taken: pair the machine again under a new name.</li>
      </ul>
      <p v-if="store.actionError" class="alert" role="alert">{{ store.actionError }}</p>
      <template #footer>
        <button type="button" @click="revoking = null">Keep</button>
        <button type="button" class="danger" :disabled="store.revoking !== null" @click="revoke(revoking)">
          Revoke
        </button>
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.block {
  display: block;
}

.revoked,
.consequences {
  margin: 0;
  padding-left: var(--xp-space-16);
}
</style>
