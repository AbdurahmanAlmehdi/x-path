<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

import { failureMessage, type CreatedToken, type TokenInfo } from '@/api/client'
import { usePeopleStore } from '@/features/people/stores/people'
import { useSessionStore } from '@/features/session/stores/session'
import Dialog from '@/ui/Dialog.vue'
import SecretWell from '@/ui/SecretWell.vue'
import { formatTime, timeAgo } from '@/ui/format'

import { connectCommand, kindLabel, mcpConfig } from '../labels'
import { useTokensStore, type NewTokenKind } from '../stores/tokens'

const session = useSessionStore()
const store = useTokensStore()
const people = usePeopleStore()

const admin = computed(() => session.can('administer'))

onMounted(() => {
  void store.load()
  if (admin.value) void people.load()
})

const making = ref<NewTokenKind | null>(null)
const name = ref('')
const creating = ref(false)
const createError = ref<string | null>(null)
/**
 * The token just made: its secret is shown this once, held by this page
 * alone, and dropped when its dialog closes or the page goes.
 */
const created = ref<CreatedToken | null>(null)
/** The token whose revoke is being confirmed. */
const revoking = ref<TokenInfo | null>(null)

onBeforeUnmount(() => {
  created.value = null
})

const origin = window.location.origin

function open(kind: NewTokenKind) {
  making.value = kind
  name.value = kind === 'cli' ? 'xp on my laptop' : 'Agent on my laptop'
  createError.value = null
}

async function create() {
  const kind = making.value
  if (!kind || name.value.trim() === '' || creating.value) return
  creating.value = true
  createError.value = null
  try {
    created.value = await store.create(name.value, kind)
    making.value = null
  } catch (failure) {
    createError.value = failureMessage(failure)
  } finally {
    creating.value = false
  }
}

async function revoke(token: TokenInfo) {
  if (await store.revoke(token.id)) revoking.value = null
}
</script>

<template>
  <section>
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Tokens</h1>
        <p class="muted">
          Make a token for xp in a terminal, on this machine or another, or for an agent that runs xp mcp. Agents can
          ask for approvals, never give them.
        </p>
      </div>
      <div class="actions">
        <button type="button" @click="open('cli')">New xp token</button>
        <button type="button" @click="open('mcp')">New agent token</button>
      </div>
    </header>
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <p v-if="store.actionError && !revoking" class="alert" role="alert">{{ store.actionError }}</p>
    <p v-if="!store.loaded" class="muted">Loading…</p>
    <div v-else class="panel table-wrap">
      <p v-if="admin" class="muted">As an admin you see and revoke the tokens of everyone.</p>
      <table data-testid="tokens">
        <thead>
          <tr>
            <th>Name</th>
            <th>Kind</th>
            <th v-if="admin">Person</th>
            <th>Made</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="token in store.tokens" :key="token.id" :data-token="token.name">
            <td>{{ token.name }}</td>
            <td>{{ kindLabel(token.kind) }}</td>
            <td v-if="admin">{{ people.nameOf(token.personId) }}</td>
            <td :title="formatTime(token.createdAt)">{{ timeAgo(token.createdAt) }}</td>
            <td>
              <span v-if="token.id === session.me?.token.id" class="muted">This browser</span>
              <button v-else type="button" @click="revoking = token">Revoke…</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      v-if="making"
      :title="making === 'cli' ? 'New xp token' : 'New agent token'"
      @close="making = null"
    >
      <form class="form" @submit.prevent="create">
        <label class="field">
          <span class="xp-type-label">Name</span>
          <input v-model="name" type="text" autocomplete="off" />
        </label>
        <p v-if="createError" class="alert" role="alert">{{ createError }}</p>
      </form>
      <template #footer>
        <button type="button" @click="making = null">Cancel</button>
        <button type="button" class="primary" :disabled="name.trim() === '' || creating" @click="create">
          Make token
        </button>
      </template>
    </Dialog>
    <Dialog v-if="created" :title="`Made “${created.info.name}”`" @close="created = null">
      <template v-if="created.info.kind === 'cli'">
        <p>Run this in a terminal to connect xp, then paste the token when it asks:</p>
        <SecretWell label="Command" :text="connectCommand(origin)" copy-label="Copy command" />
        <SecretWell label="Token" :text="created.token" copy-label="Copy token" />
      </template>
      <template v-else>
        <p>Add this to the MCP config of the agent:</p>
        <SecretWell label="MCP config" :text="mcpConfig(origin, created.token)" copy-label="Copy config" />
      </template>
      <p class="muted">The token is shown this once. Copy it now; make another if it is lost.</p>
      <template #footer>
        <button type="button" class="primary" @click="created = null">Done</button>
      </template>
    </Dialog>
    <Dialog v-if="revoking" :title="`Revoke ${revoking.name}?`" @close="revoking = null">
      <p>It stops working at once, wherever it is used.</p>
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
