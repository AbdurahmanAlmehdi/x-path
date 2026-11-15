import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { api, ApiFailure, dataOf, failureMessage, type Job } from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'
import { isFinished } from '@/ui/format'

/** What the job page can ask the engine to do. */
export type JobAction = 'cancel' | 'resume'

/** The job the job page shows, with its steps, kept up to date by its events. */
export const useJobStore = defineStore('job', () => {
  const id = ref<string | null>(null)
  const job = ref<Job | null>(null)
  const missing = ref(false)
  const error = ref<string | null>(null)
  const busy = ref<JobAction | null>(null)

  /** Whether the job has not ended: Cancel stops it. */
  const cancellable = computed(() => (job.value ? !isFinished(job.value.state) : false))

  /** Whether Resume runs the job on from its first unfinished step. */
  const resumable = computed(() =>
    ['failed', 'interrupted', 'waiting_for_resume'].includes(job.value?.state ?? ''),
  )

  async function load(jobId: string) {
    try {
      const found = await dataOf(api.GET('/jobs/{id}', { params: { path: { id: jobId } } }))
      if (id.value !== jobId) return
      job.value = found
      missing.value = false
      error.value = null
    } catch (failure) {
      if (id.value !== jobId) return
      missing.value = failure instanceof ApiFailure && failure.status === 404
      error.value = missing.value ? null : failureMessage(failure)
    }
  }

  const refresh = coalesced(() => (id.value ? load(id.value) : Promise.resolve()))

  /** Shows the job [jobId]. */
  async function open(jobId: string): Promise<void> {
    if (id.value !== jobId) {
      id.value = jobId
      job.value = null
      missing.value = false
      error.value = null
    }
    await load(jobId)
  }

  /** Follows the job's own events. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'event') {
        const { type } = item.event
        const ours = ['job.state_changed', 'job.step_changed', 'runner.lease_lost'].includes(type)
        if (!ours || payloadValue(item.event, 'jobId') !== id.value) return
      }
      void refresh()
    })
  }

  /** Asks the engine for [action]; `false` when it refused, with [error] saying why. */
  async function act(action: JobAction): Promise<boolean> {
    const jobId = id.value
    if (!jobId || busy.value) return false
    const params = { params: { path: { id: jobId } } }
    busy.value = action
    error.value = null
    try {
      job.value = await dataOf(
        action === 'cancel'
          ? api.POST('/jobs/{id}/cancel', params)
          : api.POST('/jobs/{id}/resume', { ...params, body: {} }),
      )
      return true
    } catch (failure) {
      error.value = failureMessage(failure)
      return false
    } finally {
      busy.value = null
    }
  }

  return { id, job, missing, error, busy, cancellable, resumable, open, follow, act }
})
