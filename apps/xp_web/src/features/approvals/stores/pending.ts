import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { api, dataOf, type Approval } from '@/api/client'
import { followEvents } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'

/**
 * The approvals of the engine that wait for a decision (D-13): the "needs
 * you" count of the shell's Approvals link, kept up to date by the
 * approval events.
 */
export const usePendingApprovalsStore = defineStore('pendingApprovals', () => {
  const approvals = ref<Approval[]>([])

  /** How many approvals wait. */
  const count = computed(() => approvals.value.length)

  /** Asks the engine for the approvals that wait; a failure keeps what was shown. */
  const load = coalesced(async () => {
    try {
      approvals.value = (
        await dataOf(api.GET('/approvals', { params: { query: { state: 'pending' } } }))
      ).approvals.filter((approval) => approval.state === 'pending')
    } catch {
      // The pages say what is wrong; the count keeps what it showed.
    }
  })

  /** Loads, then again when an approval is asked for, decided or expires. Returns the function that stops. */
  function follow(): () => void {
    void load()
    return followEvents((item) => {
      if (item.kind === 'resync' || item.event.type.startsWith('approval.')) void load()
    })
  }

  return { approvals, count, load, follow }
})
