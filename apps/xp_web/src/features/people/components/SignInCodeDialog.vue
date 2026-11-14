<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'

import { failureMessage, type Person, type SignInCode } from '@/api/client'
import Dialog from '@/ui/Dialog.vue'
import SecretWell from '@/ui/SecretWell.vue'
import { formatTime } from '@/ui/format'

import { usePeopleStore } from '../stores/people'

const props = defineProps<{
  person: Person
  /** Whether the person was just added. */
  added?: boolean
}>()
const emit = defineEmits<{ close: [] }>()

const people = usePeopleStore()

/**
 * The code: shown this once, held by this dialog alone, and dropped when
 * it closes. It never goes in the address bar.
 */
const code = ref<SignInCode | null>(null)
const error = ref<string | null>(null)

onMounted(async () => {
  try {
    code.value = await people.signInCode(props.person.id)
  } catch (failure) {
    error.value = failureMessage(failure)
  }
})
onBeforeUnmount(() => {
  code.value = null
})

/** The link that signs them in: the code in the fragment, which never reaches a server (D9). */
const link = computed(() =>
  code.value ? `${window.location.origin}/sign-in#code=${code.value.code}` : '',
)

function close() {
  code.value = null
  emit('close')
}
</script>

<template>
  <Dialog :title="added ? `Added ${person.name}` : `Sign-in code for ${person.name}`" @close="close">
    <p class="muted">
      Give {{ person.name }} this code. It signs them in once, within 10 minutes, and is shown only now; a new
      code ends the ones before it.
    </p>
    <p v-if="error" class="alert" role="alert">{{ error }}</p>
    <template v-else-if="code">
      <SecretWell label="Sign-in code" :text="code.code" copy-label="Copy code" />
      <SecretWell label="Or open this link" :text="link" copy-label="Copy link" />
      <p class="muted">Works until {{ formatTime(code.expiresAt) }}.</p>
    </template>
    <p v-else class="muted">Making a code…</p>
    <template #footer>
      <button type="button" class="primary" @click="close">Done</button>
    </template>
  </Dialog>
</template>
