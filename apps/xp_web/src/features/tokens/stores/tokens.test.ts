import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { tokenOf } from '@/testing/fixtures'

import { useTokensStore } from './tokens'

describe('useTokensStore', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('loads the tokens, never a secret', async () => {
    stubEngine({ 'GET /tokens': { status: 200, body: { tokens: [tokenOf()] } } })
    const store = useTokensStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.tokens.map((token) => token.name)).toEqual(['xp on my laptop'])
  })

  it('says why the tokens could not be read', async () => {
    stubUnreachableEngine()
    const store = useTokensStore()

    await store.load()

    expect(store.error).toBe('The engine did not answer. Check that it is running.')
  })

  it('hands a new token to the caller, keeps none and loads the list again', async () => {
    const seen = stubEngine({
      'POST /tokens': { status: 201, body: { info: tokenOf({ id: 'tok_3', kind: 'mcp' }), token: 'xpt_fake' } },
      'GET /tokens': { status: 200, body: { tokens: [tokenOf({ id: 'tok_3', kind: 'mcp' })] } },
    })
    const store = useTokensStore()

    const created = await store.create(' Agent ', 'mcp')

    expect(created.token).toBe('xpt_fake')
    expect(seen[0]?.body).toEqual({ name: 'Agent', kind: 'mcp' })
    await store.load()
    expect(JSON.stringify(store.$state)).not.toContain('xpt_fake')
  })

  it('throws the refusal of a new token', async () => {
    stubEngine({ 'POST /tokens': { status: 403, body: errorBody('forbidden', 'Only the app or a browser makes tokens.') } })

    await expect(useTokensStore().create('xp', 'cli')).rejects.toThrow('Only the app or a browser makes tokens.')
  })

  it('revokes a token, or says why not', async () => {
    stubEngine({
      'DELETE /tokens/tok_2': { status: 204 },
      'DELETE /tokens/tok_9': { status: 404, body: errorBody('not_found', 'No such token.') },
      'GET /tokens': { status: 200, body: { tokens: [] } },
    })
    const store = useTokensStore()

    expect(await store.revoke('tok_2')).toBe(true)
    expect(await store.revoke('tok_9')).toBe(false)
    expect(store.actionError).toBe('No such token.')
    expect(store.revoking).toBeNull()
  })
})
