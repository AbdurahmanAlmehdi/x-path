<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import type { NamedCredential } from '@/api/client'
import { useProjectsStore } from '@/features/projects/stores/projects'
import { useSessionStore } from '@/features/session/stores/session'
import Badge from '@/ui/Badge.vue'
import Dialog from '@/ui/Dialog.vue'
import { useFollowing } from '@/ui/following'

import CredentialForm from '../components/CredentialForm.vue'
import FlavorCredentialsDialog from '../components/FlavorCredentialsDialog.vue'
import {
  flavorTargets,
  kindName,
  statusOf,
  usageLabel,
  usedByLabel,
  worstStatus,
  type FlavorTarget,
} from '../labels'
import { useCredentialsStore } from '../stores/credentials'
import { useFlavorCredentialsStore } from '../stores/flavorCredentials'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const store = useCredentialsStore()
const flavors = useFlavorCredentialsStore()
const projects = useProjectsStore()

onMounted(() => {
  void store.load()
  void projects.load()
})
useFollowing(store.follow, flavors.follow, projects.follow)

const admin = computed(() => session.can('administer'))

/** The form shown: a new credential, or a new secret for one. */
const form = ref<{ replacing?: NamedCredential } | null>(null)
const renaming = ref<NamedCredential | null>(null)
const newName = ref('')
const deleting = ref<NamedCredential | null>(null)
const managing = ref<FlavorTarget | null>(null)

/** The project whose flavors are shown: `?project=`, else the first. */
const project = computed(
  () =>
    projects.projects.find((each) => each.id === route.query.project) ?? projects.projects[0] ?? null,
)
const targets = computed(() => (project.value ? flavorTargets(project.value) : []))
const severalApps = computed(() => (project.value?.profile.apps.length ?? 0) > 1)

watch(
  () => project.value?.id,
  (id) => {
    if (id) void flavors.open(id)
  },
  { immediate: true },
)

function showProject(event: Event) {
  void router.replace({ query: { ...route.query, project: (event.target as HTMLSelectElement).value } })
}

function openRename(credential: NamedCredential) {
  newName.value = credential.name
  renaming.value = credential
}

async function rename() {
  const credential = renaming.value
  if (!credential || newName.value.trim() === '') return
  if (await store.rename(credential.id, newName.value)) renaming.value = null
}

async function remove() {
  const credential = deleting.value
  if (!credential) return
  if (await store.remove(credential.id, credential.usedBy.length > 0)) deleting.value = null
}

function flavorStatus(target: FlavorTarget) {
  const status = worstStatus(flavors.of(target).map((credential) => credential.status))
  return status ? statusOf(status) : { label: 'None', tone: 'neutral' as const }
}
</script>

<template>
  <section>
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Credentials</h1>
        <p class="muted">
          Shared by every project on this engine. Checked every day and before each build; the secrets stay on the
          engine machine.
        </p>
      </div>
      <div class="actions">
        <button v-if="admin" type="button" class="primary" :disabled="form !== null" @click="form = {}">
          Add credential…
        </button>
      </div>
    </header>
    <CredentialForm
      v-if="form"
      :key="form.replacing?.id ?? 'new'"
      :replacing="form.replacing"
      @saved="form = null"
      @cancel="form = null"
    />
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <p v-if="store.commandError && !form && !renaming && !deleting" class="alert" role="alert">
      {{ store.commandError }}
    </p>
    <p v-if="store.notice" class="notice" role="status" data-testid="credentials-notice">{{ store.notice }}</p>
    <p v-if="!store.loaded" class="muted">Loading…</p>
    <div v-else-if="store.credentials.length === 0" class="panel">
      <p class="muted">No credentials yet. Add one, then assign it to the flavors that need it.</p>
    </div>
    <div v-else class="panel table-wrap">
      <table data-testid="credentials">
        <thead>
          <tr>
            <th>Name</th>
            <th>Kind</th>
            <th>Account</th>
            <th>Status</th>
            <th>Used by</th>
            <th v-if="admin"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="credential in store.credentials" :key="credential.id" :data-credential="credential.name">
            <td>{{ credential.name }}</td>
            <td>{{ kindName(credential.kind) }}</td>
            <td class="mono">{{ credential.account ?? '—' }}</td>
            <td>
              <Badge :status="statusOf(credential.status)" />
              <span v-if="credential.message" class="muted block">{{ credential.message }} {{ credential.fix }}</span>
            </td>
            <td :title="credential.usedBy.map(usageLabel).join('\n')">{{ usedByLabel(credential.usedBy.length) }}</td>
            <td v-if="admin">
              <div class="actions">
                <button type="button" :disabled="store.command !== null" @click="store.verify(credential.id)">
                  {{ store.command?.kind === 'verifying' && store.command.id === credential.id ? 'Checking…' : 'Check now' }}
                </button>
                <button type="button" @click="openRename(credential)">Rename…</button>
                <button type="button" :disabled="form !== null" @click="form = { replacing: credential }">
                  Replace secret…
                </button>
                <button type="button" @click="deleting = credential">Delete…</button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="panel" data-testid="flavors">
      <div class="flavors-header">
        <h2 class="xp-type-title">Flavors</h2>
        <select
          v-if="project && projects.projects.length > 1"
          :value="project.id"
          aria-label="Project"
          @change="showProject"
        >
          <option v-for="each in projects.projects" :key="each.id" :value="each.id">{{ each.fullName }}</option>
        </select>
        <span v-else-if="project" class="muted">{{ project.fullName }}</span>
      </div>
      <p class="muted">
        Each flavor uses at most one credential of each kind. Several flavors, of any project, can share one.
      </p>
      <p v-if="projects.loaded && !project" class="muted">Add a project to give its flavors credentials.</p>
      <p v-if="flavors.error" class="alert" role="alert">{{ flavors.error }}</p>
      <div v-if="project" class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Flavor</th>
              <th>Credentials</th>
              <th>Status</th>
              <th v-if="admin"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="target in targets" :key="`${target.app} ${target.flavor}`" :data-flavor="target.flavor">
              <td class="mono">{{ severalApps ? `${target.appName} · ${target.flavor}` : target.flavor }}</td>
              <td>
                <span v-if="flavors.of(target).length === 0" class="muted">None assigned</span>
                <span v-for="credential in flavors.of(target)" :key="credential.kind" class="block">
                  {{ kindName(credential.kind) }}: {{ credential.name ?? credential.id }}
                </span>
              </td>
              <td><Badge :status="flavorStatus(target)" /></td>
              <td v-if="admin"><button type="button" @click="managing = target">Manage…</button></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <FlavorCredentialsDialog v-if="managing" :target="managing" @close="managing = null" />
    <Dialog v-if="renaming" :title="`Rename ${renaming.name}`" @close="renaming = null">
      <p class="muted">Its secret and the flavors that use it stay.</p>
      <form class="form" @submit.prevent="rename">
        <label class="field">
          <span class="xp-type-label">Name</span>
          <input v-model="newName" type="text" maxlength="80" autocomplete="off" />
        </label>
      </form>
      <p v-if="store.commandError" class="alert" role="alert">{{ store.commandError }}</p>
      <template #footer>
        <button type="button" @click="renaming = null">Cancel</button>
        <button type="button" class="primary" :disabled="newName.trim() === '' || store.command !== null" @click="rename">
          Rename
        </button>
      </template>
    </Dialog>
    <Dialog v-if="deleting" :title="`Delete ${deleting.name}?`" @close="deleting = null">
      <ul class="consequences">
        <li>Its secret is deleted from the engine machine.</li>
        <li v-if="deleting.usedBy.length === 0">No flavor uses it.</li>
        <li v-else>
          {{ deleting.usedBy.length === 1 ? '1 flavor uses it.' : `${deleting.usedBy.length} flavors use it.` }}
          They will have no {{ kindName(deleting.kind) }} until you assign another:
          {{ deleting.usedBy.map(usageLabel).join(', ') }}
        </li>
      </ul>
      <p v-if="store.commandError" class="alert" role="alert">{{ store.commandError }}</p>
      <template #footer>
        <button type="button" @click="deleting = null">Keep it</button>
        <button type="button" class="danger" :disabled="store.command !== null" @click="remove">
          {{ deleting.usedBy.length > 0 ? 'Unassign and delete' : 'Delete' }}
        </button>
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.block {
  display: block;
}

.flavors-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-12);
  margin-bottom: var(--xp-space-4);
}

.flavors-header h2 {
  margin: 0;
}

.consequences {
  margin: 0;
  padding-left: var(--xp-space-16);
}
</style>
