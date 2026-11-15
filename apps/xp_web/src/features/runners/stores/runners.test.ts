import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { runnerOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useRunnersStore } from './runners'

describe('useRunnersStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  it('loads the runners, active and revoked apart, and counts the busy ones', async () => {
    stubEngine({
      'GET /runners': {
        status: 200,
        body: {
          runners: [
            runnerOf(),
            runnerOf({ id: 'rnr_2', name: 'linux-box', jobIds: ['job_1'] }),
            runnerOf({ id: 'rnr_3', name: 'old', status: 'revoked', revokedAt: '2026-11-12T09:00:00Z' }),
          ],
        },
      },
    })
    const store = useRunnersStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.active.map((runner) => runner.name)).toEqual(['mac-mini', 'linux-box'])
    expect(store.revoked.map((runner) => runner.name)).toEqual(['old'])
    expect(store.busy).toBe(1)
    expect(store.error).toBeNull()
  })

  it('says why the runners could not be read', async () => {
    stubUnreachableEngine()
    const store = useRunnersStore()

    await store.load()

    expect(store.error).toBe('The engine did not answer. Check that it is running.')
  })

  it('hands a pairing token to the caller and keeps none', async () => {
    const seen = stubEngine({
      'POST /runners/pairing-tokens': {
        status: 201,
        body: { token: 'xpp_fake', name: 'mac-mini', expiresAt: '2026-11-14T09:15:00Z' },
      },
    })
    const store = useRunnersStore()

    const token = await store.pairingToken('  mac-mini ')

    expect(token.token).toBe('xpp_fake')
    expect(seen[0]?.body).toEqual({ name: 'mac-mini' })
    expect(JSON.stringify(store.$state)).not.toContain('xpp_fake')
  })

  it('throws the refusal of a pairing token', async () => {
    stubEngine({
      'POST /runners/pairing-tokens': { status: 409, body: errorBody('conflict', 'The name mac-mini is taken.') },
    })

    await expect(useRunnersStore().pairingToken('mac-mini')).rejects.toThrow('The name mac-mini is taken.')
  })

  it('revokes a runner and loads again, or says why not', async () => {
    let revoked = false
    stubEngine({
      'GET /runners': () => ({
        status: 200,
        body: { runners: [runnerOf({ status: revoked ? 'revoked' : 'online' })] },
      }),
      'POST /runners/rnr_1/revoke': () => {
        revoked = true
        return { status: 200, body: runnerOf({ status: 'revoked' }) }
      },
      'POST /runners/rnr_2/revoke': { status: 403, body: errorBody('forbidden', 'A developer cannot revoke a runner.') },
    })
    const store = useRunnersStore()

    expect(await store.revoke('rnr_1')).toBe(true)
    expect(store.revoked).toHaveLength(1)
    expect(store.revoking).toBeNull()

    expect(await store.revoke('rnr_2')).toBe(false)
    expect(store.actionError).toBe('A developer cannot revoke a runner.')
  })

  it('loads again on runner events and a resync, not on others', async () => {
    const seen = stubEngine({ 'GET /runners': { status: 200, body: { runners: [] } } })
    const store = useRunnersStore()
    stops.push(store.follow())
    const feed = openEventFeed()

    feed.send('job.state_changed')
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('runner.connected', { runnerId: 'rnr_1' })
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(2)
  })
})
