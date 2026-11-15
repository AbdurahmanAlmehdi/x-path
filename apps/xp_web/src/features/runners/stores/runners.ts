import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { api, dataOf, failureMessage, type PairingToken, type Runner } from '@/api/client'
import { followEvents } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'

/**
 * The runners of the engine, kept up to date by the runner events, and
 * what an admin does with them: pair a new one, revoke one. A pairing token
 * is handed to the caller and never kept here (D-08): the dialog that shows
 * it holds it, and forgets it when it closes.
 */
export const useRunnersStore = defineStore('runners', () => {
  const runners = ref<Runner[]>([])
  const loaded = ref(false)
  const error = ref<string | null>(null)
  /** The runner being revoked. */
  const revoking = ref<string | null>(null)
  /** What the engine said when it refused a revoke. */
  const actionError = ref<string | null>(null)

  /** The runners that may run jobs, oldest first. */
  const active = computed(() => runners.value.filter((runner) => runner.status !== 'revoked'))
  /** The runners revoked. */
  const revoked = computed(() => runners.value.filter((runner) => runner.status === 'revoked'))
  /** How many runners run jobs now. */
  const busy = computed(
    () => active.value.filter((runner) => runner.status === 'online' && runner.jobIds.length > 0).length,
  )

  /** Asks the engine for the runners. */
  const load = coalesced(async () => {
    try {
      runners.value = (await dataOf(api.GET('/runners'))).runners
      error.value = null
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loaded.value = true
    }
  })

  /** Loads again on runner events and a resync. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync' || item.event.type.startsWith('runner.')) void load()
    })
  }

  /**
   * A single-use pairing token for a runner called [name], for the caller
   * to show once. Throws the engine's refusal.
   */
  function pairingToken(name: string): Promise<PairingToken> {
    return dataOf(api.POST('/runners/pairing-tokens', { body: { name: name.trim() } }))
  }

  /** Revokes the runner [id]; `true` when it went through. */
  async function revoke(id: string): Promise<boolean> {
    revoking.value = id
    actionError.value = null
    try {
      await dataOf(api.POST('/runners/{id}/revoke', { params: { path: { id } } }))
      await load()
      return true
    } catch (failure) {
      actionError.value = failureMessage(failure)
      return false
    } finally {
      revoking.value = null
    }
  }

  return {
    runners,
    loaded,
    error,
    revoking,
    actionError,
    active,
    revoked,
    busy,
    load,
    follow,
    pairingToken,
    revoke,
  }
})
