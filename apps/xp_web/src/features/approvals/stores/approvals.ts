import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { api, dataOf, failureMessage, type Approval, type ApprovalState } from '@/api/client'
import { followEvents } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'

/** The filters of the inbox. */
export type ApprovalsFilter = 'pending' | 'decided' | 'expired'

/** The filters, in the order the inbox offers them. */
export const approvalsFilters: ApprovalsFilter[] = ['pending', 'decided', 'expired']

/** The filter an approval in [state] is listed under. */
export function filterOf(state: ApprovalState): ApprovalsFilter {
  return state === 'pending' ? 'pending' : state === 'expired' ? 'expired' : 'decided'
}

/**
 * The approvals inbox: every approval of the engine, newest first, under
 * Pending, Decided and Expired, kept up to date by the approval events.
 * Deciding happens in the review of one approval.
 */
export const useApprovalsStore = defineStore('approvals', () => {
  const approvals = ref<Approval[]>([])
  const loaded = ref(false)
  const error = ref<string | null>(null)
  const filter = ref<ApprovalsFilter>('pending')
  /** The approval picked, if any: it is shown under its own filter, which follows it when it is decided. */
  const selectedId = ref<string | null>(null)

  /** The approvals under [filter]. */
  const visible = computed(() =>
    approvals.value.filter((approval) => filterOf(approval.state) === filter.value),
  )

  /** How many approvals wait. */
  const pendingCount = computed(
    () => approvals.value.filter((approval) => approval.state === 'pending').length,
  )

  /** The approval in the detail pane: the one picked, else the first under [filter]. */
  const selected = computed(
    () => visible.value.find((approval) => approval.id === selectedId.value) ?? visible.value[0] ?? null,
  )

  function followPicked() {
    const picked = approvals.value.find((approval) => approval.id === selectedId.value)
    if (picked) filter.value = filterOf(picked.state)
  }

  /** Asks the engine for the approvals. */
  const load = coalesced(async () => {
    try {
      approvals.value = (await dataOf(api.GET('/approvals'))).approvals
      error.value = null
      followPicked()
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loaded.value = true
    }
  })

  /** Shows [id] in the detail pane, under its own filter; `null` shows the first. */
  function select(id: string | null) {
    selectedId.value = id
    followPicked()
  }

  /** Lists the approvals under [next]. */
  function show(next: ApprovalsFilter) {
    filter.value = next
    selectedId.value = null
  }

  /** Loads again when an approval is asked for, decided or expires. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync' || item.event.type.startsWith('approval.')) void load()
    })
  }

  return {
    approvals,
    loaded,
    error,
    filter,
    selectedId,
    visible,
    pendingCount,
    selected,
    load,
    select,
    show,
    follow,
  }
})
