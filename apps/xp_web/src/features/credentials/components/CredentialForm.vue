<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue'

import type {
  CreateCredentialRequest,
  CredentialKind,
  NamedCredential,
  ReplaceCredentialRequest,
} from '@/api/client'
import { formatSize } from '@/ui/format'

import { base64Of, kindName, namedKinds, secretFields, type SecretField } from '../labels'
import { useCredentialsStore } from '../stores/credentials'

const props = defineProps<{
  /** The credential whose secret this replaces; a new credential without it. */
  replacing?: NamedCredential
  /** The kind to start with. */
  kind?: CredentialKind
}>()
const emit = defineEmits<{ saved: []; cancel: [] }>()

const store = useCredentialsStore()

type NamedKind = Exclude<CredentialKind, 'github'>

const name = ref('')
const kind = ref<NamedKind>((props.replacing?.kind ?? props.kind ?? 'asc_key') as NamedKind)
const keyKind = ref<'team' | 'individual'>('team')
/** What was typed in the fields of the kind, secrets included: this form alone holds them. */
const typed = reactive<Record<string, string>>({})
/** The files picked, by field. Their bytes are read only to send them, and never shown. */
const files = new Map<string, File>()
/** What the page says about each file picked: its name and size, never what is in it. */
const chosen = reactive<Record<string, string>>({})

const fields = computed<SecretField[]>(() => secretFields[kind.value])

/** Forgets every secret of the form. */
function forget() {
  for (const key of Object.keys(typed)) delete typed[key]
  for (const key of Object.keys(chosen)) delete chosen[key]
  files.clear()
}

watch(kind, forget)
onBeforeUnmount(forget)

function pick(field: SecretField, event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) {
    files.delete(field.name)
    delete chosen[field.name]
    return
  }
  files.set(field.name, file)
  chosen[field.name] = `${file.name} · ${formatSize(file.size)}`
}

function filled(field: SecretField): boolean {
  if (field.input === 'textFile' || field.input === 'binaryFile') return chosen[field.name] !== undefined
  return (typed[field.name] ?? '').trim() !== ''
}

const complete = computed(
  () =>
    (props.replacing !== undefined || name.value.trim() !== '') &&
    fields.value.every((field) => field.optional || filled(field)),
)

/** The secret fields of the kind as the API reads them; files are read now, straight into the request. */
async function secretsOf(): Promise<Record<string, string>> {
  const secrets: Record<string, string> = {}
  for (const field of fields.value) {
    const file = files.get(field.name)
    if (field.input === 'textFile' && file) secrets[field.name] = await file.text()
    else if (field.input === 'binaryFile' && file) secrets[field.name] = base64Of(await file.arrayBuffer())
    else if (filled(field)) secrets[field.name] = typed[field.name]!.trim()
  }
  if (kind.value === 'asc_key') secrets.keyKind = keyKind.value
  return secrets
}

async function save() {
  if (!complete.value || store.command !== null) return
  const secrets = await secretsOf()
  const saved = props.replacing
    ? await store.replace(props.replacing.id, { kind: kind.value, ...secrets } as ReplaceCredentialRequest)
    : await store.create({ name: name.value.trim(), kind: kind.value, ...secrets } as CreateCredentialRequest)
  if (!saved) return
  forget()
  emit('saved')
}
</script>

<template>
  <form class="panel form" data-testid="credential-form" autocomplete="off" @submit.prevent="save">
    <h2 class="xp-type-title">
      {{ replacing ? `Replace the secret of ${replacing.name}` : 'Add a credential' }}
    </h2>
    <p class="muted">
      {{
        replacing
          ? 'Its name and the flavors that use it stay. The engine checks the new secret first; nothing changes if the check fails. The old secret is not shown.'
          : 'The engine checks it with the place it is for before it keeps it. Nothing is stored if the check fails.'
      }}
    </p>
    <template v-if="!replacing">
      <label class="field">
        <span class="xp-type-label">Name</span>
        <input v-model="name" type="text" maxlength="80" placeholder="Team App Store key" autocomplete="off" />
      </label>
      <label class="field">
        <span class="xp-type-label">Kind</span>
        <select v-model="kind">
          <option v-for="each in namedKinds" :key="each" :value="each">{{ kindName(each) }}</option>
        </select>
      </label>
      <label v-if="kind === 'asc_key'" class="field">
        <span class="xp-type-label">Key type</span>
        <select v-model="keyKind">
          <option value="team">Team key</option>
          <option value="individual">Individual key</option>
        </select>
      </label>
    </template>
    <label v-for="field in fields" :key="`${kind} ${field.name}`" class="field">
      <span class="xp-type-label">{{ field.label }}</span>
      <template v-if="field.input === 'textFile' || field.input === 'binaryFile'">
        <input type="file" :accept="field.accept" :data-field="field.name" @change="pick(field, $event)" />
        <span v-if="chosen[field.name]" class="muted" data-testid="file-chosen">{{ chosen[field.name] }}</span>
      </template>
      <input
        v-else-if="field.input === 'secret'"
        v-model="typed[field.name]"
        type="password"
        autocomplete="new-password"
        spellcheck="false"
        :data-field="field.name"
      />
      <input
        v-else
        v-model="typed[field.name]"
        type="text"
        autocomplete="off"
        spellcheck="false"
        :data-field="field.name"
      />
    </label>
    <p v-if="store.commandError" class="alert" role="alert">Not saved: {{ store.commandError }}</p>
    <div class="actions">
      <button type="button" @click="forget(); emit('cancel')">Cancel</button>
      <button type="submit" class="primary" :disabled="!complete || store.command !== null">
        {{ store.command?.kind === 'saving' ? 'Checking…' : 'Check and save' }}
      </button>
    </div>
  </form>
</template>
