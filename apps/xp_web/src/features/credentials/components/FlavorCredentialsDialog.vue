<script setup lang="ts">
import { computed, ref } from 'vue'

import type { Credential, CredentialKind } from '@/api/client'
import Badge from '@/ui/Badge.vue'
import Dialog from '@/ui/Dialog.vue'

import { kindName, namedKinds, statusOf, type FlavorTarget } from '../labels'
import { useCredentialsStore } from '../stores/credentials'
import { useFlavorCredentialsStore } from '../stores/flavorCredentials'

const props = defineProps<{ target: FlavorTarget }>()
const emit = defineEmits<{ close: [] }>()

const named = useCredentialsStore()
const store = useFlavorCredentialsStore()

const kind = ref<CredentialKind>('asc_key')
const credentialId = ref('')
const everyFlavor = ref(false)
const replace = ref(false)

const mine = computed(() => store.of(props.target))
/** The named credentials of the kind picked. */
const candidates = computed(() => named.credentials.filter((credential) => credential.kind === kind.value))

function pickKind(next: CredentialKind) {
  kind.value = next
  credentialId.value = candidates.value[0]?.id ?? ''
}
pickKind(kind.value)

async function assign() {
  if (credentialId.value === '') return
  await store.assign(props.target, kind.value, credentialId.value, {
    allFlavors: everyFlavor.value,
    replace: everyFlavor.value && replace.value,
  })
}

function change(credential: Credential) {
  pickKind(credential.kind)
  credentialId.value = credential.id
}
</script>

<template>
  <Dialog :title="`Credentials of ${target.flavor}`" @close="emit('close')">
    <p class="muted">
      The credential this flavor uses for each kind, with what the last checks found: does it work, and can it reach
      this flavor's app.
    </p>
    <ul class="assigned" data-testid="flavor-credentials">
      <li v-if="mine.length === 0" class="muted">None assigned</li>
      <li v-for="credential in mine" :key="credential.kind">
        <span>{{ kindName(credential.kind) }}: <strong>{{ credential.name ?? credential.id }}</strong></span>
        <Badge :status="statusOf(credential.status)" />
        <span v-if="credential.message" class="muted">{{ credential.message }} {{ credential.fix }}</span>
        <span class="actions">
          <button type="button" @click="change(credential)">Change…</button>
          <button type="button" :disabled="store.assigning" @click="store.unassign(target, credential.kind)">
            Remove from this flavor
          </button>
        </span>
      </li>
    </ul>
    <form class="form" @submit.prevent="assign">
      <label class="field">
        <span class="xp-type-label">Kind</span>
        <select :value="kind" @change="pickKind(($event.target as HTMLSelectElement).value as CredentialKind)">
          <option v-for="each in namedKinds" :key="each" :value="each">{{ kindName(each) }}</option>
        </select>
      </label>
      <label class="field">
        <span class="xp-type-label">Credential</span>
        <select v-model="credentialId" :disabled="candidates.length === 0">
          <option v-for="credential in candidates" :key="credential.id" :value="credential.id">
            {{ credential.name }}
          </option>
        </select>
        <span v-if="candidates.length === 0" class="muted">No {{ kindName(kind) }} yet. Add one on this page first.</span>
      </label>
      <fieldset class="field use-for">
        <legend class="xp-type-label">Use for</legend>
        <label><input v-model="everyFlavor" type="radio" :value="false" /> This flavor</label>
        <label><input v-model="everyFlavor" type="radio" :value="true" /> Every flavor of {{ target.appName }}</label>
        <label v-if="everyFlavor"><input v-model="replace" type="checkbox" /> Replace existing</label>
        <span v-if="everyFlavor" class="muted">
          {{
            replace
              ? `Every flavor of the app uses this ${kindName(kind)}, even those that have their own.`
              : `Flavors that have their own ${kindName(kind)} keep it.`
          }}
        </span>
      </fieldset>
      <p v-if="store.kept.length > 0" class="notice" role="status">
        {{ store.kept.join(', ') }} kept their own credential. Tick “Replace existing” to change them too.
      </p>
      <p v-if="store.assignError" class="alert" role="alert">{{ store.assignError }}</p>
    </form>
    <template #footer>
      <button type="button" @click="emit('close')">Done</button>
      <button type="button" class="primary" :disabled="credentialId === '' || store.assigning" @click="assign">
        Assign
      </button>
    </template>
  </Dialog>
</template>

<style scoped>
.assigned {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-6);
  margin: 0;
  padding: 0;
  list-style: none;
}

.assigned li {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xp-space-8);
}

.use-for {
  margin: 0;
  padding: 0;
  border: 0;
}
</style>
