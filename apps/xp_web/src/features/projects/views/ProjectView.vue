<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRoute } from 'vue-router'

import { useSessionStore } from '@/features/session/stores/session'
import RunList from '@/features/runs/components/RunList.vue'
import { useFollowing } from '@/ui/following'

import { useProjectStore } from '../stores/project'
import { useWorkflowsStore } from '../stores/workflows'

const route = useRoute()
const session = useSessionStore()
const store = useProjectStore()
const workflows = useWorkflowsStore()

const projectId = computed(() => String(route.params.id))

watch(
  projectId,
  (id) => {
    void store.open(id)
    void workflows.know([id])
  },
  { immediate: true },
)
useFollowing(store.follow, workflows.follow)

const subtitle = computed(() => {
  const project = store.project
  if (!project) return ''
  const apps = project.profile.apps.length
  return `${project.defaultBaseBranch} · ${apps === 1 ? '1 app' : `${apps} apps`}`
})

function platformsOf(app: { hasAndroid: boolean; hasIos: boolean }): string {
  return [app.hasAndroid ? 'Android' : null, app.hasIos ? 'iOS' : null].filter(Boolean).join(' · ')
}
</script>

<template>
  <section>
    <p v-if="store.missing" class="notice">This project is no longer on the engine.</p>
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <template v-if="store.project">
      <header class="page-header">
        <div>
          <h1 class="xp-type-headline">{{ store.project.fullName }}</h1>
          <p class="muted">{{ subtitle }}</p>
        </div>
        <div class="actions">
          <span class="muted" data-testid="running">
            {{ store.running > 0 ? `${store.running} running` : 'Nothing running' }}
          </span>
          <RouterLink :to="{ name: 'releases', params: { id: store.project.id } }" class="button">Releases</RouterLink>
          <RouterLink :to="{ name: 'tests', params: { id: store.project.id } }" class="button">Tests</RouterLink>
          <RouterLink :to="{ name: 'workflows', params: { id: store.project.id } }" class="button">Workflows</RouterLink>
          <RouterLink
            v-if="session.can('develop')"
            :to="{ name: 'dispatch', params: { id: store.project.id } }"
            class="button primary"
          >
            Dispatch…
          </RouterLink>
        </div>
      </header>

      <p v-if="store.project.profile.apps.length === 0" class="notice">No Flutter app found.</p>
      <section v-for="app in store.project.profile.apps" :key="app.path" class="panel">
        <h2 class="xp-type-title">{{ app.name }}</h2>
        <p class="muted">
          path {{ app.path }} · Flutter {{ app.flutterVersion ?? 'not pinned' }} · store country
          {{ app.storeCountry }}
          <template v-if="app.version"> · version <span class="mono">{{ app.version }}</span></template>
          <template v-if="platformsOf(app)"> · {{ platformsOf(app) }}</template>
        </p>
        <p v-if="app.flavors.length === 0" class="muted">No flavor to show.</p>
        <div v-else class="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Flavor</th>
                <th scope="col">Android</th>
                <th scope="col">iOS</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="flavor in app.flavors" :key="flavor.name">
                <td>
                  {{ flavor.name }}
                  <span v-if="flavor.prod" class="xp-type-label muted">production</span>
                </td>
                <td class="mono">{{ flavor.androidAppId ?? '—' }}</td>
                <td class="mono">{{ flavor.iosBundleId ?? '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="panel">
        <header class="page-header runs-header">
          <h2 class="xp-type-title">Recent runs</h2>
          <RouterLink :to="{ name: 'project-runs', params: { id: store.project.id } }">All runs</RouterLink>
        </header>
        <RunList
          :runs="store.runs"
          empty="Nothing has run yet. Dispatch a workflow to see its runs here."
        />
      </section>
    </template>
    <p v-else-if="!store.missing && !store.error" class="muted">Loading…</p>
  </section>
</template>

<style scoped>
.runs-header {
  margin-bottom: var(--xp-space-4);
  align-items: baseline;
}
</style>
