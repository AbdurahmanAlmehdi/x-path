<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

import { failureMessage, type PairingToken } from '@/api/client'
import { useSettingsStore } from '@/features/settings/stores/settings'
import Dialog from '@/ui/Dialog.vue'
import SecretWell from '@/ui/SecretWell.vue'
import { formatCountdown, formatTime } from '@/ui/format'

import { pairingCommand } from '../labels'
import { useRunnersStore } from '../stores/runners'

const emit = defineEmits<{ close: [] }>()

const runners = useRunnersStore()
const settings = useSettingsStore()

const name = ref('')
const creating = ref(false)
const error = ref<string | null>(null)
/**
 * The pairing token: shown this once, held by this dialog alone, and
 * dropped when it closes.
 */
const token = ref<PairingToken | null>(null)
const now = ref(Date.now())
let ticking: ReturnType<typeof setInterval> | undefined

onMounted(() => {
  void settings.loadRunnerUrl()
  ticking = setInterval(() => {
    now.value = Date.now()
  }, 10_000)
})
onBeforeUnmount(() => {
  clearInterval(ticking)
  token.value = null
})

const command = computed(() =>
  token.value
    ? pairingCommand(token.value, window.location.origin, settings.runnerUrl ?? undefined)
    : null,
)
const expired = computed(() => token.value !== null && Date.parse(token.value.expiresAt) <= now.value)

async function create(runnerName: string) {
  if (runnerName.trim() === '' || creating.value) return
  creating.value = true
  error.value = null
  try {
    token.value = await runners.pairingToken(runnerName)
    now.value = Date.now()
  } catch (failure) {
    error.value = failureMessage(failure)
  } finally {
    creating.value = false
  }
}

function close() {
  token.value = null
  emit('close')
}
</script>

<template>
  <Dialog title="Pair a runner" @close="close">
    <p class="muted">XPath makes a pairing token for the name. It works once, for 15 minutes, and is shown only now.</p>
    <form v-if="!token" class="form" @submit.prevent="create(name)">
      <label class="field">
        <span class="xp-type-label">Name</span>
        <input v-model="name" type="text" placeholder="mac-mini" autocomplete="off" spellcheck="false" />
      </label>
      <p v-if="error" class="alert" role="alert">{{ error }}</p>
    </form>
    <template v-else-if="command">
      <SecretWell :label="`Pairing token for ${token.name}`" :text="token.token" copy-label="Copy token" />
      <SecretWell label="On the runner, run" :text="command.text" copy-label="Copy command" />
      <p v-if="command.onlyHere" class="notice" data-testid="only-here">
        This address only works on the engine's machine. Set the address runners reach the engine at in
        <RouterLink to="/settings">Settings</RouterLink>; pairing commands carry it.
      </p>
      <div v-if="expired" class="actions">
        <p class="alert">Expired before it was used.</p>
        <button type="button" @click="create(token.name)">New token</button>
      </div>
      <p v-else class="muted" data-testid="expires">
        Works once; expires in {{ formatCountdown(token.expiresAt, now) }} ({{ formatTime(token.expiresAt) }}).
      </p>
    </template>
    <template #footer>
      <button type="button" @click="close">{{ token ? 'Done' : 'Cancel' }}</button>
      <button
        v-if="!token"
        type="button"
        class="primary"
        :disabled="name.trim() === '' || creating"
        @click="create(name)"
      >
        {{ creating ? 'Creating…' : 'Create pairing token' }}
      </button>
    </template>
  </Dialog>
</template>
