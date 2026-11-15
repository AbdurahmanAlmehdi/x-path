import { defineStore } from 'pinia'
import { ref, shallowRef } from 'vue'

import { api, dataOf, failureMessage, type Run, type RunState } from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'
import { useWorkflowsStore } from '@/features/projects/stores/workflows'

/** What the runs are filtered by; nothing set shows every run. */
export interface RunsFilter {
  project?: string
  workflow?: string
  state?: RunState
}

/** How many runs a page holds. */
export const runsPageSize = 50

/**
 * The runs of the Runs pages, newest first, wherever they were dispatched
 * from, as [RunsFilter] says; kept up to date by the runs dispatched and
 * the jobs that change.
 */
export const useRunsStore = defineStore('runs', () => {
  // Shallow: a load compares it with the filter it was for.
  const filter = shallowRef<RunsFilter>({})
  const runs = ref<Run[]>([])
  /** The `before` of the next page, when there may be one. */
  const next = ref<string | null>(null)
  const loaded = ref(false)
  const loadingMore = ref(false)
  const error = ref<string | null>(null)
  const workflows = useWorkflowsStore()

  async function page(wanted: RunsFilter, limit: number, before?: string) {
    const result = await dataOf(
      api.GET('/runs', {
        params: {
          query: {
            project: wanted.project,
            workflow: wanted.workflow,
            state: wanted.state,
            limit,
            before,
          },
        },
      }),
    )
    void workflows.know(result.runs.map((run) => run.projectId))
    return result
  }

  async function reload(wanted: RunsFilter, limit: number) {
    try {
      const result = await page(wanted, limit)
      if (filter.value !== wanted) return
      runs.value = result.runs
      next.value = result.next ?? null
      error.value = null
    } catch (failure) {
      if (filter.value === wanted) error.value = failureMessage(failure)
    } finally {
      if (filter.value === wanted) loaded.value = true
    }
  }

  /** Shows the runs that match [wanted]. */
  async function load(wanted: RunsFilter): Promise<void> {
    filter.value = wanted
    runs.value = []
    next.value = null
    loaded.value = false
    await reload(wanted, runsPageSize)
  }

  /** Adds the next page of runs. */
  async function more(): Promise<void> {
    const before = next.value
    if (!before || loadingMore.value) return
    const wanted = filter.value
    loadingMore.value = true
    try {
      const result = await page(wanted, runsPageSize, before)
      if (filter.value !== wanted) return
      runs.value = [...runs.value, ...result.runs]
      next.value = result.next ?? null
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loadingMore.value = false
    }
  }

  // The runs shown, again: as many as there are now (one page at least).
  const refresh = coalesced(() =>
    reload(filter.value, Math.min(Math.max(runs.value.length, runsPageSize), 200)),
  )

  /** Loads again when a run of the filter's project is dispatched or one of its jobs changes. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'event') {
        const { type } = item.event
        if (type !== 'run.dispatched' && type !== 'job.state_changed') return
        const project = filter.value.project
        if (project && payloadValue(item.event, 'projectId') !== project) return
      }
      void refresh()
    })
  }

  return { filter, runs, next, loaded, loadingMore, error, load, more, follow }
})
