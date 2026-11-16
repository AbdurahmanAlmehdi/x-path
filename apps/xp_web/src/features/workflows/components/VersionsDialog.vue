<script setup lang="ts">
import { computed } from 'vue'

import Dialog from '@/ui/Dialog.vue'
import { formatTime } from '@/ui/format'

import { useWorkflowBuilderStore } from '../stores/builder'
import DiffView from './DiffView.vue'

/**
 * The versions of the open workflow, as the Mac app's: any two compared,
 * the one before the newest against the newest first, and the older one of
 * a workflow of the project's own saved again as the newest ([canRestore]).
 */
const props = defineProps<{ canRestore: boolean }>()

const emit = defineEmits<{ close: []; restore: [version: number] }>()

const store = useWorkflowBuilderStore()

const versions = computed(() => store.workflow?.versions ?? [])
const newest = computed(() => versions.value.at(-1)?.version ?? 1)
const diff = computed(() => store.versionDiff)
/** The one before the newest, or the newest of a workflow saved once. */
const before = computed(() => versions.value.at(-2)?.version ?? newest.value)
const from = computed(() => diff.value?.from ?? before.value)
const to = computed(() => diff.value?.to ?? newest.value)
const restorable = computed(
  () => props.canRestore && store.workflow?.builtin === false && diff.value !== null && diff.value.from !== newest.value,
)

// Before the first render: the last compare may be of another workflow.
void store.compareVersions(before.value, newest.value)

function pick(which: 'from' | 'to', event: Event) {
  const version = Number((event.target as HTMLSelectElement).value)
  void store.compareVersions(which === 'from' ? version : from.value, which === 'to' ? version : to.value)
}
</script>

<template>
  <Dialog :title="`Versions of ${store.workflow?.name ?? 'the workflow'}`" wide @close="emit('close')">
    <div class="pick">
      <label class="field">
        <span class="xp-type-label">From</span>
        <select :value="from" @change="pick('from', $event)">
          <option v-for="version in versions" :key="version.version" :value="version.version">
            Version {{ version.version }} · {{ formatTime(version.createdAt) }}
          </option>
        </select>
      </label>
      <label class="field">
        <span class="xp-type-label">To</span>
        <select :value="to" @change="pick('to', $event)">
          <option v-for="version in versions" :key="version.version" :value="version.version">
            Version {{ version.version }} · {{ formatTime(version.createdAt) }}
          </option>
        </select>
      </label>
    </div>
    <p v-if="store.versionError" class="alert" role="alert">{{ store.versionError }}</p>
    <DiffView v-else-if="diff" :before="diff.before" :after="diff.after" />
    <p v-else class="muted">Loading…</p>
    <template #footer>
      <button v-if="restorable" type="button" @click="emit('restore', diff!.from)">
        Restore version {{ diff!.from }}
      </button>
      <button type="button" class="primary" @click="emit('close')">Close</button>
    </template>
  </Dialog>
</template>

<style scoped>
.pick {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: var(--xp-space-12);
}
</style>
