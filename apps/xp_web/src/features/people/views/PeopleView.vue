<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'

import { failureMessage, type Person, type PersonRole } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'
import Dialog from '@/ui/Dialog.vue'
import { formatTime, timeAgo } from '@/ui/format'

import SignInCodeDialog from '../components/SignInCodeDialog.vue'
import { roles, usePeopleStore } from '../stores/people'

const session = useSessionStore()
const store = usePeopleStore()

onMounted(() => store.load())

const admin = computed(() => session.can('administer'))

const adding = ref(false)
const name = ref('')
const role = ref<PersonRole>('developer')
const addError = ref<string | null>(null)
const saving = ref(false)
/** The person a sign-in code is shown for, and whether they were just added. */
const coding = ref<{ person: Person; added: boolean } | null>(null)
/** The person whose removal is being confirmed. */
const removing = ref<Person | null>(null)
/** Bumped when the engine refuses a role, so the menus show the role again. */
const refused = ref(0)

function openAdd() {
  name.value = ''
  role.value = 'developer'
  addError.value = null
  adding.value = true
}

async function add() {
  if (name.value.trim() === '' || saving.value) return
  saving.value = true
  addError.value = null
  try {
    const person = await store.add(name.value, role.value)
    adding.value = false
    coding.value = { person, added: true }
  } catch (failure) {
    addError.value = failureMessage(failure)
  } finally {
    saving.value = false
  }
}

async function changeRole(person: Person, event: Event) {
  const next = (event.target as HTMLSelectElement).value as PersonRole
  if (next === person.role) return
  if (!(await store.setRole(person.id, next))) refused.value++
  else if (person.id === session.person?.id) await session.refresh()
}

async function remove(person: Person) {
  if (await store.remove(person.id)) removing.value = null
}
</script>

<template>
  <section>
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">People</h1>
        <p class="muted">Everyone who signs in to this engine, and what their role lets them do.</p>
      </div>
      <div class="actions">
        <button v-if="admin" type="button" class="primary" @click="openAdd">Add person…</button>
      </div>
    </header>
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <p v-if="store.actionError && !removing" class="alert" role="alert" data-testid="people-error">
      {{ store.actionError }}
    </p>
    <p v-if="!store.loaded" class="muted">Loading…</p>
    <div v-else class="panel table-wrap">
      <table data-testid="people">
        <thead>
          <tr>
            <th>Name</th>
            <th>Role</th>
            <th>Added</th>
            <th v-if="admin"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="person in store.active" :key="person.id" :data-person="person.name">
            <td>
              {{ person.name }}
              <span v-if="person.id === session.person?.id" class="muted"> · you</span>
            </td>
            <td>
              <select
                v-if="admin"
                :key="`${person.role} ${refused}`"
                :value="person.role"
                :aria-label="`Role of ${person.name}`"
                :disabled="store.changing === person.id"
                @change="changeRole(person, $event)"
              >
                <option v-for="each in roles" :key="each" :value="each">{{ each }}</option>
              </select>
              <span v-else>{{ person.role }}</span>
            </td>
            <td :title="formatTime(person.createdAt)">{{ timeAgo(person.createdAt) }}</td>
            <td v-if="admin">
              <div class="actions">
                <button type="button" @click="coding = { person, added: false }">Sign-in code…</button>
                <button type="button" @click="removing = person">Remove…</button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="store.removed.length > 0" class="panel">
      <h2 class="xp-type-title">Removed</h2>
      <p class="muted">Approvals and runs keep their names.</p>
      <ul class="removed">
        <li v-for="person in store.removed" :key="person.id">{{ person.name }}</li>
      </ul>
    </div>

    <Dialog v-if="adding" title="Add a person" @close="adding = false">
      <form class="form" @submit.prevent="add">
        <label class="field">
          <span class="xp-type-label">Name</span>
          <input v-model="name" type="text" maxlength="80" autocomplete="off" />
        </label>
        <label class="field">
          <span class="xp-type-label">Role</span>
          <select v-model="role">
            <option v-for="each in roles" :key="each" :value="each">{{ each }}</option>
          </select>
        </label>
        <p class="muted">They sign in with a one-time code, shown next.</p>
        <p v-if="addError" class="alert" role="alert">{{ addError }}</p>
      </form>
      <template #footer>
        <button type="button" @click="adding = false">Cancel</button>
        <button type="button" class="primary" :disabled="name.trim() === '' || saving" @click="add">Add</button>
      </template>
    </Dialog>
    <SignInCodeDialog v-if="coding" :person="coding.person" :added="coding.added" @close="coding = null" />
    <Dialog v-if="removing" :title="`Remove ${removing.name}?`" @close="removing = null">
      <ul class="removed">
        <li>They can no longer sign in, and every token of theirs stops working at once.</li>
        <li>Approvals and runs keep their name.</li>
      </ul>
      <p v-if="store.actionError" class="alert" role="alert">{{ store.actionError }}</p>
      <template #footer>
        <button type="button" @click="removing = null">Keep</button>
        <button type="button" class="danger" :disabled="store.changing !== null" @click="remove(removing)">
          Remove
        </button>
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.removed {
  margin: 0;
  padding-left: var(--xp-space-16);
}
</style>
