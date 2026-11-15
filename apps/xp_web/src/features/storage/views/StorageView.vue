<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'

import type { StorageCategory } from '@/api/client'
import { useProjectsStore } from '@/features/projects/stores/projects'
import { useSessionStore } from '@/features/session/stores/session'
import Dialog from '@/ui/Dialog.vue'
import { formatSize, formatTime, timeAgo } from '@/ui/format'

import { buildsLabel, categoryName, categoryRule } from '../labels'
import { useStorageStore } from '../stores/storage'

const session = useSessionStore()
const store = useStorageStore()
const projects = useProjectsStore()

onMounted(() => {
  void store.load()
  void projects.load()
})

const freeing = ref(false)
const picked = ref<StorageCategory[]>([])
// A number field gives a number once edited, a string until then.
const keepPerFlavor = ref<string | number>('')
const logDays = ref<string | number>('')

const retention = computed(() => store.report?.retention ?? { keepPerFlavor: 5, logDays: 90 })

watch(
  retention,
  (now) => {
    keepPerFlavor.value = String(now.keepPerFlavor)
    logDays.value = String(now.logDays)
  },
  { immediate: true },
)

/** The categories retention would give something back in. */
const reclaimable = computed(() =>
  (store.report?.categories ?? []).filter((category) => category.reclaimableBytes > 0),
)
const pickedBytes = computed(() =>
  reclaimable.value
    .filter((category) => picked.value.includes(category.category))
    .reduce((sum, category) => sum + category.reclaimableBytes, 0),
)

function wholeNumber(value: string | number): number | null {
  const text = String(value).trim()
  return /^\d+$/.test(text) && Number(text) >= 1 ? Number(text) : null
}
const retentionValid = computed(
  () => wholeNumber(keepPerFlavor.value) !== null && wholeNumber(logDays.value) !== null,
)

function openFree() {
  picked.value = reclaimable.value.map((category) => category.category)
  freeing.value = true
}

async function free() {
  if (await store.free(picked.value)) freeing.value = false
}

async function saveRetention() {
  const keep = wholeNumber(keepPerFlavor.value)
  const days = wholeNumber(logDays.value)
  if (keep === null || days === null) return
  await store.saveRetention({ keepPerFlavor: keep, logDays: days })
}
</script>

<template>
  <section>
    <header class="page-header">
      <div>
        <h1 class="xp-type-headline">Storage</h1>
        <p v-if="store.report" class="muted" :title="formatTime(store.report.generatedAt)">
          Measured {{ timeAgo(store.report.generatedAt) }}
        </p>
      </div>
      <div class="actions">
        <button type="button" @click="store.load()">Measure again</button>
        <button
          v-if="session.can('administer')"
          type="button"
          class="primary"
          :disabled="reclaimable.length === 0 || store.busy !== null"
          @click="openFree"
        >
          Free up space…
        </button>
      </div>
    </header>
    <p v-if="store.error" class="alert" role="alert">{{ store.error }}</p>
    <p v-if="store.actionError && !freeing" class="alert" role="alert">{{ store.actionError }}</p>
    <p v-if="store.notice" class="notice" role="status" data-testid="storage-notice">{{ store.notice }}</p>
    <p v-for="failure in store.failures" :key="failure" class="alert">{{ failure }}</p>
    <p v-if="!store.loaded" class="muted">Loading…</p>
    <template v-else-if="store.report">
      <div class="panel">
        <h2 class="xp-type-title" data-testid="storage-hero">
          {{ formatSize(store.reclaimable) }} of {{ formatSize(store.used) }} reclaimable
        </h2>
        <p class="muted">
          Pinned artifacts, releases not over yet and the newest builds of each flavor are always kept.
        </p>
      </div>
      <div class="panel table-wrap">
        <h2 class="xp-type-title">What the engine keeps</h2>
        <table>
          <thead>
            <tr><th>Category</th><th>Items</th><th>Used</th><th>Reclaimable</th></tr>
          </thead>
          <tbody>
            <tr v-for="category in store.report.categories" :key="category.category">
              <td>
                {{ categoryName(category.category) }}
                <span class="muted block">{{ categoryRule(category.category, retention) }}</span>
              </td>
              <td class="mono">{{ category.items }}</td>
              <td class="mono">{{ formatSize(category.usedBytes) }}</td>
              <td class="mono">{{ formatSize(category.reclaimableBytes) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-if="store.report.flavors.length > 0" class="panel table-wrap">
        <h2 class="xp-type-title">Artifacts by app and flavor</h2>
        <table>
          <thead>
            <tr><th>Project</th><th>App</th><th>Flavor</th><th>Builds</th><th>Used</th><th>Reclaimable</th></tr>
          </thead>
          <tbody>
            <tr v-for="flavor in store.report.flavors" :key="`${flavor.projectId} ${flavor.app} ${flavor.flavor}`">
              <td>{{ projects.nameOf(flavor.projectId) }}</td>
              <td class="mono">{{ flavor.app }}</td>
              <td class="mono">{{ flavor.flavor || '—' }}</td>
              <td>{{ buildsLabel(flavor.builds, flavor.artifacts) }}</td>
              <td class="mono">{{ formatSize(flavor.usedBytes) }}</td>
              <td class="mono">{{ formatSize(flavor.reclaimableBytes) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <form class="panel form" @submit.prevent="saveRetention">
        <h2 class="xp-type-title">Retention</h2>
        <p class="muted">Logs past their days go every night; artifacts only with Free up space.</p>
        <div class="retention">
          <label class="field">
            <span class="xp-type-label">Builds kept per flavor</span>
            <input v-model="keepPerFlavor" type="number" min="1" :readonly="!session.can('administer')" />
          </label>
          <label class="field">
            <span class="xp-type-label">Days of logs</span>
            <input v-model="logDays" type="number" min="1" :readonly="!session.can('administer')" />
          </label>
        </div>
        <p v-if="!retentionValid" class="alert">Both need a whole number of at least 1.</p>
        <div v-if="session.can('administer')" class="actions">
          <button type="submit" :disabled="!retentionValid || store.busy !== null">Save</button>
        </div>
      </form>
    </template>

    <Dialog v-if="freeing" title="Free up space" @close="freeing = false">
      <p class="muted">XPath deletes what retention gives back in the categories you pick. It cannot be undone.</p>
      <label v-for="category in reclaimable" :key="category.category" class="choice">
        <input v-model="picked" type="checkbox" :value="category.category" />
        {{ categoryName(category.category) }} · {{ formatSize(category.reclaimableBytes) }}
      </label>
      <p v-if="store.actionError" class="alert" role="alert">{{ store.actionError }}</p>
      <template #footer>
        <button type="button" @click="freeing = false">Keep everything</button>
        <button
          type="button"
          class="danger"
          :disabled="picked.length === 0 || store.busy !== null"
          @click="free"
        >
          Free {{ formatSize(pickedBytes) }}
        </button>
      </template>
    </Dialog>
  </section>
</template>

<style scoped>
.block {
  display: block;
}

.retention {
  display: flex;
  flex-wrap: wrap;
  gap: var(--xp-space-16);
}

.choice {
  display: flex;
  align-items: center;
  gap: var(--xp-space-6);
}
</style>
