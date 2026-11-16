import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  api,
  dataOf,
  type FreeSpaceResult,
  type RetentionSettings,
  type StorageCategory,
  type StorageReport,
} from '@/api/client'
import { useCommand, useLoad } from '@/api/requests'
import { formatSize } from '@/ui/format'

/**
 * What the engine keeps on disk and what retention would give back, its
 * retention settings, and freeing space (an admin's: the engine decides).
 */
export const useStorageStore = defineStore('storage', () => {
  const report = ref<StorageReport | null>(null)
  /**
   * What is on its way to the engine ([busy]), and what it said when it
   * refused the last command ([error]).
   */
  const command = useCommand<'freeing' | 'savingRetention' | null>(null)
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
  const { loaded, error, load } = useLoad(async () => {
    report.value = await dataOf(api.GET('/storage'))
  })

  /**
   * Runs [send] as [kind], then measures again; `true` when it went
   * through, with [notice] saying what it did.
   */
  async function run(kind: 'freeing' | 'savingRetention', send: () => Promise<string>): Promise<boolean> {
    notice.value = null
    const done = await command.run(kind, async () => {
      notice.value = await send()
      await load()
      return true
    })
    return done ?? false
  }

  /** Deletes what retention gives back in [categories]; `true` when it went through. */
  function free(categories: StorageCategory[]): Promise<boolean> {
    return run('freeing', async () => {
      const result: FreeSpaceResult = await dataOf(
        api.POST('/storage/free', { body: { dryRun: false, categories } }),
      )
      const bytes = result.categories.reduce((sum, category) => sum + category.bytes, 0)
      failures.value = result.failures
      return `Freed ${formatSize(bytes)}`
    })
  }

  /** Keeps [settings] as the retention; `true` when it went through. */
  function saveRetention(settings: Required<RetentionSettings>): Promise<boolean> {
    return run('savingRetention', async () => {
      const now = await dataOf(api.PUT('/storage/retention', { body: settings }))
      if (report.value) report.value = { ...report.value, retention: now }
      return 'Retention saved'
    })
  }

  return {
    report,
    loaded,
    error,
    busy: command.busy,
    actionError: command.error,
    notice,
    failures,
    used,
    reclaimable,
    load,
    free,
    saveRetention,
  }
})
