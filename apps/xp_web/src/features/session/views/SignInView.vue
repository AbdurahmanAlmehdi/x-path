<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { safeNext } from '@/app/next'

import { useSessionStore } from '../stores/session'

const session = useSessionStore()
const route = useRoute()
const router = useRouter()

const code = ref('')
const failure = ref<string | null>(null)
const busy = ref(false)

/**
 * The code `xp dashboard` and the Mac app put in the fragment
 * (`/sign-in#code=…`), which never reaches a server log (D9). It is taken
 * out of the address and the history at once, so Back or a bookmark never
 * shows it again.
 */
function takeCodeFromFragment(): string | null {
  const fragment = new URLSearchParams(window.location.hash.slice(1))
  const given = fragment.get('code')
  if (given === null) return null
  const { pathname, search } = window.location
  window.history.replaceState(window.history.state, '', `${pathname}${search}`)
  return given
}

async function submit() {
  const given = code.value.trim()
  if (given === '' || busy.value) return
  busy.value = true
  failure.value = null
  try {
    failure.value = await session.signIn(given)
  } catch {
    failure.value = 'The engine did not answer. Check that it is running.'
  } finally {
    busy.value = false
  }
  if (failure.value === null) {
    await router.replace(safeNext(route.query.next))
  }
}

onMounted(async () => {
  const given = takeCodeFromFragment()
  if (given === null) return
  code.value = given
  await submit()
})
</script>

<template>
  <main class="sign-in">
    <form class="card" aria-labelledby="sign-in-title" @submit.prevent="submit">
      <h1 id="sign-in-title" class="xp-type-headline">Sign in to XPath</h1>
      <p class="xp-type-body hint">
        Enter the sign-in code an admin gave you, or open the dashboard with
        <code>xp dashboard</code> or from the Mac app's settings.
      </p>
      <label class="xp-type-label" for="code">Sign-in code</label>
      <input
        id="code"
        v-model="code"
        name="code"
        autocomplete="one-time-code"
        autocapitalize="characters"
        spellcheck="false"
        placeholder="XXXX-XXXX-XXXX-XXXX"
        :aria-invalid="failure !== null"
        :aria-describedby="failure ? 'sign-in-failure' : undefined"
        required
      />
      <p v-if="failure" id="sign-in-failure" class="failure" role="alert">{{ failure }}</p>
      <button type="submit" class="primary" :disabled="busy">
        {{ busy ? 'Signing in…' : 'Sign in' }}
      </button>
    </form>
  </main>
</template>

<style scoped>
.sign-in {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: var(--xp-space-16);
}

.card {
  width: min(100%, 400px);
  display: flex;
  flex-direction: column;
  gap: var(--xp-space-12);
  padding: var(--xp-space-32);
  background: var(--xp-color-surface-raised);
  border: var(--xp-border-width-hairline) solid var(--xp-color-border-default);
  border-radius: var(--xp-radius-lg);
  box-shadow: var(--xp-elevation-2);
}

.hint {
  color: var(--xp-color-text-secondary);
  margin: 0;
}

input {
  font: var(--xp-type-code-lg);
  letter-spacing: 0.06em;
}

.failure {
  margin: 0;
  color: var(--xp-color-negative-default);
}
</style>
