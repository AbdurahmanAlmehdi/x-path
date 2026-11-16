import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api, dataOf, doneOf, type CreatedToken, type TokenInfo } from '@/api/client'
import { useCommand, useLoad } from '@/api/requests'

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
  /**
   * The token being revoked ([busy]), and what the engine said when it
   * refused a revoke ([error]).
   */
  const revoking = useCommand<string | null>(null)

  /** Asks the engine for the tokens. */
  const { loaded, error, load } = useLoad(async () => {
    tokens.value = (await dataOf(api.GET('/tokens'))).tokens
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
    const revoked = await revoking.run(id, async () => {
      await doneOf(api.DELETE('/tokens/{id}', { params: { path: { id } } }))
      await load()
      return true
    })
    return revoked ?? false
  }

  return {
    tokens,
    loaded,
    error,
    revoking: revoking.busy,
    actionError: revoking.error,
    load,
    create,
    revoke,
  }
})
