import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api, dataOf, doneOf, failureMessage, type CreatedToken, type TokenInfo } from '@/api/client'
import { coalesced } from '@/app/coalesce'

/** The kinds of token the dashboard makes (D17). */
export type NewTokenKind = 'cli' | 'mcp'

/**
 * The tokens of the signed-in person (an admin's: everyone's), never their
 * secrets, and making and revoking them (D17). A new token's secret is
 * handed to the caller and never kept here: the dialog that shows it holds
 * it, and forgets it when it closes.
 */
export const useTokensStore = defineStore('tokens', () => {
  const tokens = ref<TokenInfo[]>([])
  const loaded = ref(false)
  const error = ref<string | null>(null)
  /** The token being revoked. */
  const revoking = ref<string | null>(null)
  /** What the engine said when it refused a revoke. */
  const actionError = ref<string | null>(null)

  /** Asks the engine for the tokens. */
  const load = coalesced(async () => {
    try {
      tokens.value = (await dataOf(api.GET('/tokens'))).tokens
      error.value = null
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loaded.value = true
    }
  })

  /**
   * Makes a token of [kind] called [name], for the caller to show once.
   * Throws the engine's refusal.
   */
  async function create(name: string, kind: NewTokenKind): Promise<CreatedToken> {
    const created = await dataOf(api.POST('/tokens', { body: { name: name.trim(), kind } }))
    void load()
    return created
  }

  /** Revokes the token [id]; `true` when it went through. */
  async function revoke(id: string): Promise<boolean> {
    revoking.value = id
    actionError.value = null
    try {
      await doneOf(api.DELETE('/tokens/{id}', { params: { path: { id } } }))
      await load()
      return true
    } catch (failure) {
      actionError.value = failureMessage(failure)
      return false
    } finally {
      revoking.value = null
    }
  }

  return { tokens, loaded, error, revoking, actionError, load, create, revoke }
})
