import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  api,
  ApiFailure,
  dataOf,
  errorMessage,
  failureMessage,
  type Approval,
  type Job,
  type Release,
} from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'

/**
 * How long the review waits before Approve works, so a click or a key
 * meant for something else never approves (the Mac app's rule).
 */
export const armingDelay = 1000

/** A decision of the review. */
export type Decision = 'approve' | 'deny'

/**
 * One approval: what it is bound to (the job that waits and the release it
 * builds), kept up to date by its events, and its review, the only place
 * the app decides it. The first decision wins (D-13): an approval decided
 * elsewhere, or that expired, while the review is open shows who won.
 */
export const useApprovalStore = defineStore('approval', () => {
  const id = ref<string | null>(null)
  const approval = ref<Approval | null>(null)
  /** The job that waits for it, when the engine says. */
  const job = ref<Job | null>(null)
  /** The release that job builds, if any. */
  const release = ref<Release | null>(null)
  const missing = ref(false)
  const error = ref<string | null>(null)

  /** Whether the review is open. */
  const reviewing = ref(false)
  /** Whether the arming delay of the review is over. */
  const armed = ref(false)
  /** The decision on its way to the engine. */
  const deciding = ref<Decision | null>(null)
  /** What the engine said when it refused a decision. */
  const decisionError = ref<string | null>(null)
  let arming: ReturnType<typeof setTimeout> | undefined

  const pending = computed(() => approval.value?.state === 'pending')

  /** Whether the review approves now. */
  const canApprove = computed(
    () => reviewing.value && armed.value && pending.value && deciding.value === null,
  )

  /** Whether the review denies now. */
  const canDeny = computed(() => reviewing.value && pending.value && deciding.value === null)

  async function loadSubject(approvalId: string, jobId: string | undefined) {
    if (!jobId) return
    try {
      const found = await dataOf(api.GET('/jobs/{id}', { params: { path: { id: jobId } } }))
      if (id.value !== approvalId) return
      job.value = found
      if (!found.releaseId) return
      const built = await dataOf(
        api.GET('/releases/{id}', { params: { path: { id: found.releaseId } } }),
      )
      if (id.value === approvalId) release.value = built
    } catch {
      // The approval says what matters; its job and release only add to it.
    }
  }

  async function load(approvalId: string) {
    try {
      const found = await dataOf(
        api.GET('/approvals/{id}', { params: { path: { id: approvalId } } }),
      )
      if (id.value !== approvalId) return
      const first = approval.value === null
      approval.value = found
      missing.value = false
      error.value = null
      if (first) await loadSubject(approvalId, found.jobId)
    } catch (failure) {
      if (id.value !== approvalId) return
      missing.value = failure instanceof ApiFailure && failure.status === 404
      error.value = missing.value ? null : failureMessage(failure)
    }
  }

  const refresh = coalesced(() => (id.value ? load(id.value) : Promise.resolve()))

  /** Closes the review. */
  function close() {
    clearTimeout(arming)
    reviewing.value = false
    armed.value = false
    decisionError.value = null
  }

  /** Shows the approval [approvalId]. */
  async function open(approvalId: string): Promise<void> {
    if (id.value !== approvalId) {
      close()
      id.value = approvalId
      approval.value = null
      job.value = null
      release.value = null
      missing.value = false
      error.value = null
    }
    await load(approvalId)
  }

  /** Follows the approval's own events. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'event') {
        if (!item.event.type.startsWith('approval.')) return
        if (payloadValue(item.event, 'approvalId') !== id.value) return
      }
      void refresh()
    })
  }

  /** Opens the review: Approve works [armingDelay] later. */
  function review() {
    close()
    reviewing.value = true
    arming = setTimeout(() => {
      armed.value = true
    }, armingDelay)
  }

  /**
   * Sends [decision], with [reason] for a denial. `true` when it is the
   * decision that counts; else [approval] says who won, or [decisionError]
   * why the engine refused.
   */
  async function decide(decision: Decision, reason?: string): Promise<boolean> {
    const approvalId = id.value
    const allowed = decision === 'approve' ? canApprove.value : canDeny.value
    if (!approvalId || !allowed) return false
    const why = reason?.trim()
    const request = {
      params: { path: { id: approvalId } },
      body: decision === 'deny' && why ? { reason: why } : {},
    }
    deciding.value = decision
    decisionError.value = null
    try {
      const { data, error: body, response } =
        decision === 'approve'
          ? await api.POST('/approvals/{id}/approve', request)
          : await api.POST('/approvals/{id}/deny', request)
      if (data) {
        approval.value = data
        return true
      }
      // Decided elsewhere first, or expired: the engine says how it stands.
      const standing = (body as { approval?: Approval } | undefined)?.approval
      if (response.status === 409 && standing) approval.value = standing
      else decisionError.value = errorMessage(body, response.status)
      return false
    } catch (failure) {
      decisionError.value = failureMessage(failure)
      return false
    } finally {
      deciding.value = null
    }
  }

  return {
    id,
    approval,
    job,
    release,
    missing,
    error,
    reviewing,
    armed,
    deciding,
    decisionError,
    pending,
    canApprove,
    canDeny,
    open,
    follow,
    review,
    close,
    decide,
  }
})
