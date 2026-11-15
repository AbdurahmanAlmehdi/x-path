<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'

import type { Finding } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'
import Badge from '@/ui/Badge.vue'
import Dialog from '@/ui/Dialog.vue'
import type { StatusLabel } from '@/ui/format'

import { useAddProjectStore, type ProjectSource } from '../stores/addProject'

const router = useRouter()
const session = useSessionStore()
const store = useAddProjectStore()

onMounted(() => store.reset())

const source = ref<ProjectSource>('remote')
const location = ref('')
const removing = ref(false)

const busy = computed(() => store.status === 'adding' || store.status === 'scanning')
const reviewing = computed(() => store.project !== null && store.status !== 'discarded')

const severities: Record<Finding['severity'], StatusLabel> = {
  error: { label: 'Error', tone: 'negative' },
  warning: { label: 'Warning', tone: 'caution' },
  info: { label: 'Note', tone: 'neutral' },
}

function add() {
  if (location.value.trim() === '' || busy.value) return
  void store.add(source.value, location.value)
}

function useSshUrl() {
  if (store.sshUrl) void store.add('path', location.value, store.sshUrl)
}

async function discard() {
  removing.value = false
  if (await store.discard()) location.value = ''
}

function done() {
  const added = store.project
  store.reset()
  if (added) void router.push({ name: 'project', params: { id: added.id } })
}
</script>

<template>
  <section>
    <header class="page-header">
      <h1 class="xp-type-headline">Add project</h1>
    </header>

    <template v-if="reviewing && store.project">
      <div class="panel" data-testid="scan-review">
        <h2 class="xp-type-title">Review the scan of {{ store.project.fullName }}</h2>
        <p class="muted">This is what XPath found. Fix errors in the repository and scan again; warnings and notes can wait.</p>
        <p v-if="store.project.findings.length === 0" class="muted">The scan found nothing to fix.</p>
        <ul v-else class="findings">
          <li v-for="finding in store.project.findings" :key="`${finding.code} ${finding.path ?? ''} ${finding.flavor ?? ''}`">
            <Badge :status="severities[finding.severity]" />
            <span>{{ finding.message }} <span class="muted">{{ finding.fix }}</span></span>
          </li>
        </ul>
        <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
        <div class="actions">
          <button type="button" class="primary" @click="done">Done</button>
          <button v-if="session.can('develop')" type="button" :disabled="busy" @click="store.rescan()">
            {{ store.status === 'scanning' ? 'Scanning…' : 'Scan again' }}
          </button>
          <button v-if="session.can('administer')" type="button" @click="removing = true">Remove project</button>
        </div>
      </div>
    </template>

    <div v-else-if="!session.can('develop')" class="panel" data-testid="cannot-add">
      <p>Your role cannot add projects: it takes the developer role or higher.</p>
    </div>

    <form v-else class="panel form" data-testid="add-project" @submit.prevent="add">
      <p v-if="store.status === 'discarded'" class="notice" role="status">The project was removed.</p>
      <fieldset class="field sources">
        <legend class="xp-type-label">From</legend>
        <label class="choice"><input v-model="source" type="radio" value="remote" /> A git URL</label>
        <label class="choice"><input v-model="source" type="radio" value="path" /> A folder on the engine's machine</label>
      </fieldset>
      <label class="field">
        <span class="xp-type-label">{{ source === 'remote' ? 'Repository' : 'Folder' }}</span>
        <input
          v-model="location"
          type="text"
          spellcheck="false"
          autocomplete="off"
          :placeholder="source === 'remote' ? 'owner/app or git@host:team/app.git' : '/Users/you/src/app'"
        />
      </label>
      <p class="muted">
        <template v-if="source === 'remote'">
          A GitHub repository (owner/name or its URL) is read with the engine's GitHub token; any other host over SSH,
          with the engine's own key.
        </template>
        <template v-else>
          The folder has to be on the machine the engine runs on. XPath reads it and never writes to it; builds run
          from the engine's own copy.
        </template>
      </p>
      <template v-if="store.status === 'failed' && store.error">
        <div v-if="store.sshUrl" class="notice" role="alert">
          <p>
            XPath reads repositories outside GitHub over SSH, with the engine's own key. Add the folder from
            <code>{{ store.sshUrl }}</code> instead? Your clone is not changed.
          </p>
          <button type="button" @click="useSshUrl">Use the SSH URL</button>
        </div>
        <p v-else class="alert" role="alert" data-testid="add-error">
          The engine could not add this: {{ store.error }}
        </p>
      </template>
      <div class="actions">
        <button type="submit" class="primary" :disabled="location.trim() === '' || busy">
          {{ store.status === 'adding' ? 'Scanning…' : 'Add and scan' }}
        </button>
      </div>
    </form>

    <Dialog v-if="removing && store.project" :title="`Remove ${store.project.fullName}?`" @close="removing = false">
      <ul class="findings">
        <li>The engine forgets the project and what its scan found.</li>
        <li>Nothing in the folder or on GitHub changes.</li>
      </ul>
      <template #footer>
        <button type="button" @click="removing = false">Keep</button>
        <button type="button" class="danger" @click="discard">Remove project</button>
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.sources {
  margin: 0;
  padding: 0;
  border: 0;
}

.choice {
  display: inline-flex;
  align-items: center;
  gap: var(--xp-space-4);
  margin-right: var(--xp-space-12);
}

.findings {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-6);
  margin: 0 0 var(--xp-space-12);
  padding-left: 0;
  list-style: none;
}

.findings li {
  display: flex;
  gap: var(--xp-space-8);
  align-items: flex-start;
}
</style>
