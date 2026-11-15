import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { api, ApiFailure, dataOf, failureMessage, type Run } from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'
import { isFinished } from '@/ui/format'

/** What the run page can ask the engine to do. */
export type RunAction = 'cancel' | 'runAgain' | 'rerunFailed'

/**
 * The run the run page shows, with the state of each of its jobs, kept up
 * to date by the job and approval events of its project.
 */
export const useRunStore = defineStore('run', () => {
  const id = ref<string | null>(null)
  const run = ref<Run | null>(null)
  const missing = ref(false)
  const error = ref<string | null>(null)
  /** The action under way, if any. */
  const busy = ref<RunAction | null>(null)

  /** Whether a job of the run has not ended: Cancel stops it. */
  const cancellable = computed(() => run.value?.jobs.some((job) => !isFinished(job.state)) ?? false)

  /** Whether a job can run again from the step that failed. */
  const rerunnable = computed(
    () =>
      run.value?.jobs.some((job) =>
        ['failed', 'interrupted', 'waiting_for_resume'].includes(job.state),
      ) ?? false,
  )

  async function load(runId: string) {
    try {
      const found = await dataOf(api.GET('/runs/{id}', { params: { path: { id: runId } } }))
      if (id.value !== runId) return
      run.value = found
      missing.value = false
      error.value = null
    } catch (failure) {
      if (id.value !== runId) return
      missing.value = failure instanceof ApiFailure && failure.status === 404
      error.value = missing.value ? null : failureMessage(failure)
    }
  }

  const refresh = coalesced(() => (id.value ? load(id.value) : Promise.resolve()))

  /** Shows the run [runId]. */
  async function open(runId: string): Promise<void> {
    if (id.value !== runId) {
      id.value = runId
      run.value = null
      missing.value = false
      error.value = null
    }
    await load(runId)
  }

  /** Follows the job and approval events of the run's project. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'event') {
        const { type } = item.event
        if (!(type === 'job.state_changed' || type.startsWith('approval.'))) return
        if (payloadValue(item.event, 'projectId') !== run.value?.projectId) return
      }
      void refresh()
    })
  }

  /**
   * Asks the engine for [action] on the run. The run it answers with: the
   * new run of "Run again", else this one; `null` when it refused, with
   * [error] saying why.
   */
  async function act(action: RunAction): Promise<Run | null> {
    const runId = id.value
    if (!runId || busy.value) return null
    const params = { params: { path: { id: runId } } }
    busy.value = action
    error.value = null
    try {
      const answer = await dataOf(
        action === 'cancel'
          ? api.POST('/runs/{id}/cancel', params)
          : action === 'runAgain'
            ? api.POST('/runs/{id}/run-again', params)
            : api.POST('/runs/{id}/rerun-failed', params),
      )
      if (answer.id === runId) run.value = answer
      return answer
    } catch (failure) {
      error.value = failureMessage(failure)
      return null
    } finally {
      busy.value = null
    }
  }

  return { id, run, missing, error, busy, cancellable, rerunnable, open, follow, act }
})
