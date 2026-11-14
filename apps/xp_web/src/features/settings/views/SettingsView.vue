<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'

import { useSessionStore } from '@/features/session/stores/session'
import Dialog from '@/ui/Dialog.vue'

import { useSettingsStore } from '../stores/settings'

const session = useSessionStore()
const store = useSettingsStore()

onMounted(() => store.load())

const admin = computed(() => session.can('administer'))
const publicUrl = ref('')
const runnerUrl = ref('')
/** The GitHub token being typed: it goes to the engine and is never shown back. */
const githubToken = ref('')
const removingGitHub = ref(false)

watch(
  () => store.publicUrl,
  (url) => {
    publicUrl.value = url ?? ''
  },
  { immediate: true },
)
watch(
  () => store.runnerUrl,
  (url) => {
    runnerUrl.value = url ?? ''
  },
  { immediate: true },
)

const githubLine = computed(() => {
  const github = store.github
  if (!github) return null
  if (!github.stored) return 'The engine has no GitHub token, so it cannot add projects from GitHub.'
  const why = [github.message, github.fix].filter(Boolean).join(' ')
  switch (github.status) {
    case 'rejected':
      return `GitHub refused the engine's token: ${why}`
    case 'unreachable':
      return `GitHub could not check the engine's token: ${why}`
    default:
      return github.login ? `Connected to GitHub as ${github.login}.` : 'Connected to GitHub.'
  }
})

async function saveGitHub() {
  if (githubToken.value.trim() === '') return
  if (await store.saveGitHubToken(githubToken.value)) githubToken.value = ''
}

async function removeGitHub() {
  if (await store.removeGitHubToken()) removingGitHub.value = false
}
</script>

<template>
  <section>
    <header class="page-header">
      <h1 class="xp-type-headline">Settings</h1>
    </header>
    <p v-if="!store.loaded" class="muted">Loading…</p>
    <template v-else>
      <form class="panel form" data-testid="public-url" @submit.prevent="store.setPublicUrl(publicUrl)">
        <h2 class="xp-type-title">Public URL</h2>
        <p class="muted">
          The HTTPS address browsers reach this engine at through a proxy, such as Caddy or tailscale serve. The
          engine has no TLS of its own, so signing in from another machine works only through it.
        </p>
        <p class="muted" role="status">
          {{ store.publicUrl ? `Browsers sign in through ${store.publicUrl}.` : 'No public URL is set: browsers sign in on the engine machine only.' }}
        </p>
        <label v-if="admin" class="field">
          <span class="xp-type-label">URL</span>
          <input v-model="publicUrl" type="url" placeholder="https://xpath.example.com" spellcheck="false" />
        </label>
        <p v-if="store.errors.publicUrl" class="alert" role="alert">{{ store.errors.publicUrl }}</p>
        <div v-if="admin" class="actions">
          <button type="submit" :disabled="publicUrl.trim() === '' || store.saving !== null">Save</button>
          <button
            v-if="store.publicUrl"
            type="button"
            :disabled="store.saving !== null"
            @click="store.setPublicUrl(null)"
          >
            Clear
          </button>
        </div>
      </form>

      <form class="panel form" data-testid="runner-url" @submit.prevent="store.setRunnerUrl(runnerUrl)">
        <h2 class="xp-type-title">Runner URL</h2>
        <p class="muted">
          The address runners on other machines reach this engine at, for example a Tailscale name. Every pairing
          command carries it.
        </p>
        <p class="muted" role="status">
          {{ store.runnerUrl ? `Runners reach the engine at ${store.runnerUrl}.` : 'No runner URL is set: pairing commands use the address this page reaches the engine at.' }}
        </p>
        <label v-if="admin" class="field">
          <span class="xp-type-label">URL</span>
          <input v-model="runnerUrl" type="url" placeholder="http://mac-mini.local:7480" spellcheck="false" />
        </label>
        <p v-if="store.runnerUrlWarning" class="notice">{{ store.runnerUrlWarning }}</p>
        <p v-if="store.errors.runnerUrl" class="alert" role="alert">{{ store.errors.runnerUrl }}</p>
        <p class="muted">Runners paired already keep their address; pair them again to move them.</p>
        <div v-if="admin" class="actions">
          <button type="submit" :disabled="runnerUrl.trim() === '' || store.saving !== null">Save</button>
          <button
            v-if="store.runnerUrl"
            type="button"
            :disabled="store.saving !== null"
            @click="store.setRunnerUrl(null)"
          >
            Clear
          </button>
        </div>
      </form>

      <form class="panel form" data-testid="github" @submit.prevent="saveGitHub">
        <h2 class="xp-type-title">GitHub</h2>
        <p class="muted">
          The engine adds projects, keeps its copies and pushes with one GitHub token, shared by every project. The
          token stays on the engine machine and is checked with GitHub before it is saved.
        </p>
        <p v-if="githubLine" role="status" data-testid="github-status">{{ githubLine }}</p>
        <template v-if="admin">
          <label class="field">
            <span class="xp-type-label">Token</span>
            <input
              v-model="githubToken"
              type="password"
              autocomplete="off"
              spellcheck="false"
              placeholder="ghp_… or github_pat_… with the repo scope"
            />
          </label>
          <p class="muted">Import runs gh auth token on the engine machine; log in there with gh auth login first.</p>
        </template>
        <p v-if="store.errors.github" class="alert" role="alert">Not saved: {{ store.errors.github }}</p>
        <div v-if="admin" class="actions">
          <button type="submit" :disabled="githubToken.trim() === '' || store.saving !== null">
            {{ store.saving === 'github' ? 'Asking GitHub…' : 'Check and save' }}
          </button>
          <button type="button" :disabled="store.saving !== null" @click="store.importGitHubToken()">
            Import from GitHub CLI
          </button>
          <button
            v-if="store.github?.stored"
            type="button"
            :disabled="store.saving !== null"
            @click="removingGitHub = true"
          >
            Remove token
          </button>
        </div>
      </form>
    </template>

    <Dialog v-if="removingGitHub" title="Remove the GitHub token?" @close="removingGitHub = false">
      <ul class="consequences">
        <li>The engine can no longer clone, tag or open pull requests, so jobs that need GitHub fail.</li>
        <li>The token stays valid on GitHub; revoke it there if it leaked.</li>
      </ul>
      <p v-if="store.errors.github" class="alert" role="alert">{{ store.errors.github }}</p>
      <template #footer>
        <button type="button" @click="removingGitHub = false">Keep</button>
        <button type="button" class="danger" :disabled="store.saving !== null" @click="removeGitHub">
          Remove token
        </button>
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.consequences {
  margin: 0;
  padding-left: var(--xp-space-16);
}
</style>
