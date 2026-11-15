<script setup lang="ts">
import { onMounted, ref } from 'vue'

import Dialog from '@/ui/Dialog.vue'

import { certificateName, type FlavorTarget } from '../labels'
import { type TeamCertificate, useFlavorCredentialsStore } from '../stores/flavorCredentials'

const props = defineProps<{ target: FlavorTarget; project: string }>()
const emit = defineEmits<{ close: [] }>()

const store = useFlavorCredentialsStore()
const name = ref(certificateName(props.project, props.target.flavor))

onMounted(() => store.resetCertificate())

async function create() {
  if (name.value.trim() === '' || store.creating) return
  if (await store.createCertificate(props.target, name.value)) emit('close')
}

/** A certificate of the team as the engine's refusal describes it: name, serial and expiry. */
function describe(certificate: TeamCertificate): string {
  return [
    certificate.name ?? 'A certificate',
    `serial ${certificate.serialNumber}`,
    certificate.expirationDate ? `expires ${certificate.expirationDate.slice(0, 10)}` : undefined,
  ]
    .filter(Boolean)
    .join(' · ')
}
</script>

<template>
  <Dialog :title="`Create certificate for ${target.flavor}`" @close="emit('close')">
    <p class="muted">
      The engine creates a new Apple Distribution certificate with this flavor's App Store Connect key and assigns it.
      Apple allows a team three.
    </p>
    <form class="form" @submit.prevent="create">
      <label class="field">
        <span class="xp-type-label">Name</span>
        <input v-model="name" type="text" maxlength="80" autocomplete="off" />
      </label>
    </form>
    <div v-if="store.certificateLimit" class="alert limit" role="alert" data-testid="certificate-limit">
      <p>
        The team has {{ store.certificateLimit.certificates.length }} distribution certificates, Apple's limit is
        {{ store.certificateLimit.limit }}:
      </p>
      <ul>
        <li v-for="certificate in store.certificateLimit.certificates" :key="certificate.id">
          {{ describe(certificate) }}
        </li>
      </ul>
      <p>
        Revoke one in App Store Connect (Certificates, Identifiers &amp; Profiles) and create again, or add the identity
        of one of them with Add credential… as an Apple Distribution identity.
      </p>
    </div>
    <p v-else-if="store.certificateError" class="alert" role="alert">{{ store.certificateError }}</p>
    <template #footer>
      <button type="button" @click="emit('close')">Cancel</button>
      <button type="button" class="primary" :disabled="name.trim() === '' || store.creating" @click="create">
        {{ store.creating ? 'Creating…' : 'Create certificate' }}
      </button>
    </template>
  </Dialog>
</template>

<style scoped>
.limit {
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-6);
}

.limit p,
.limit ul {
  margin: 0;
}

.limit ul {
  padding-left: var(--xp-space-16);
}
</style>
