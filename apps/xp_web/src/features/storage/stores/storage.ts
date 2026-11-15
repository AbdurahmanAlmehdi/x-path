import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  api,
  dataOf,
  failureMessage,
  type FreeSpaceResult,
  type RetentionSettings,
  type StorageCategory,
  type StorageReport,
} from '@/api/client'
import { coalesced } from '@/app/coalesce'
import { formatSize } from '@/ui/format'

/**
 * What the engine keeps on disk and what retention would give back, its
 * retention settings, and freeing space (an admin's: the engine decides).
 */
export const useStorageStore = defineStore('storage', () => {
  const report = ref<StorageReport | null>(null)
  const loaded = ref(false)
  const error = ref<string | null>(null)
  /** What is on its way to the engine. */
  const busy = ref<'freeing' | 'savingRetention' | null>(null)
  /** What the engine said when it refused the last command. */
  const actionError = ref<string | null>(null)
  /** What the last command did, when it went through. */
  const notice = ref<string | null>(null)
  /** What could not be deleted in the last free. */
  const failures = ref<string[]>([])

  const used = computed(() =>
    (report.value?.categories ?? []).reduce((sum, category) => sum + category.usedBytes, 0),
  )
  const reclaimable = computed(() =>
    (report.value?.categories ?? []).reduce((sum, category) => sum + category.reclaimableBytes, 0),
  )

  /** Measures again. */
  const load = coalesced(async () => {
    try {
      report.value = await dataOf(api.GET('/storage'))
      error.value = null
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loaded.value = true
    }
  })

  function begin(command: 'freeing' | 'savingRetention') {
    busy.value = command
    actionError.value = null
    notice.value = null
  }

  /** Deletes what retention gives back in [categories]; `true` when it went through. */
  async function free(categories: StorageCategory[]): Promise<boolean> {
    begin('freeing')
    try {
      const result: FreeSpaceResult = await dataOf(
        api.POST('/storage/free', { body: { dryRun: false, categories } }),
      )
      const bytes = result.categories.reduce((sum, category) => sum + category.bytes, 0)
      notice.value = `Freed ${formatSize(bytes)}`
      failures.value = result.failures
      await load()
      return true
    } catch (failure) {
      actionError.value = failureMessage(failure)
      return false
    } finally {
      busy.value = null
    }
  }

  /** Keeps [settings] as the retention; `true` when it went through. */
  async function saveRetention(settings: Required<RetentionSettings>): Promise<boolean> {
    begin('savingRetention')
    try {
      const now = await dataOf(api.PUT('/storage/retention', { body: settings }))
      if (report.value) report.value = { ...report.value, retention: now }
      notice.value = 'Retention saved'
      await load()
      return true
    } catch (failure) {
      actionError.value = failureMessage(failure)
      return false
    } finally {
      busy.value = null
    }
  }

  return {
    report,
    loaded,
    error,
    busy,
    actionError,
    notice,
    failures,
    used,
    reclaimable,
    load,
    free,
    saveRetention,
  }
})
