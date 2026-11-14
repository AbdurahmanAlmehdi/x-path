import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { flavorCredentialOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useFlavorCredentialsStore } from './flavorCredentials'

describe('useFlavorCredentialsStore', () => {
  const stops: Array<() => void> = []
  const dev = { app: '.', appName: 'app', flavor: 'dev' }
  const prod = { app: '.', appName: 'app', flavor: 'prod' }

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  const list = {
    'GET /projects/prj_1/credentials': {
      status: 200,
      body: { credentials: [flavorCredentialOf(), flavorCredentialOf({ flavor: 'prod', kind: 'play_sa' })] },
    },
  }

  it('loads the credentials of the flavors of a project, by flavor', async () => {
    stubEngine(list)
    const store = useFlavorCredentialsStore()

    await store.open('prj_1')

    expect(store.loaded).toBe(true)
    expect(store.of(dev).map((credential) => credential.kind)).toEqual(['keystore'])
    expect(store.of(prod).map((credential) => credential.kind)).toEqual(['play_sa'])
  })

  it('says why they could not be read, and drops an answer for a project no longer shown', async () => {
    stubUnreachableEngine()
    const store = useFlavorCredentialsStore()
    await store.open('prj_1')
    expect(store.error).toBe('The engine did not answer. Check that it is running.')

    stubEngine(list)
    const first = store.open('prj_1')
    const second = store.open('prj_2')
    await Promise.all([first, second])
    expect(store.projectId).toBe('prj_2')
    expect(store.credentials).toEqual([])
  })

  it('assigns a credential to a flavor, or every flavor of its app, and says which kept theirs', async () => {
    const seen = stubEngine({
      ...list,
      'PUT /projects/prj_1/flavors/dev/credentials/keystore': {
        status: 200,
        body: { assigned: [flavorCredentialOf()], kept: [flavorCredentialOf({ flavor: 'prod' })] },
      },
    })
    const store = useFlavorCredentialsStore()
    expect(await store.assign(dev, 'keystore', 'crd_1')).toBe(false)

    await store.open('prj_1')
    expect(await store.assign(dev, 'keystore', 'crd_1', { allFlavors: true })).toBe(true)

    const put = seen.find((request) => request.method === 'PUT')
    expect(put?.search).toBe('?app=.')
    expect(put?.body).toEqual({ credentialId: 'crd_1', allFlavors: true, replace: false })
    expect(store.kept).toEqual(['prod'])
    expect(store.assigning).toBe(false)
  })

  it('unassigns, and says why the engine refused', async () => {
    stubEngine({
      ...list,
      'DELETE /projects/prj_1/flavors/dev/credentials/keystore': { status: 204 },
      'DELETE /projects/prj_1/flavors/prod/credentials/play_sa': {
        status: 403,
        body: errorBody('forbidden', 'A developer cannot unassign a credential.'),
      },
    })
    const store = useFlavorCredentialsStore()
    await store.open('prj_1')

    expect(await store.unassign(dev, 'keystore')).toBe(true)
    expect(await store.unassign(prod, 'play_sa')).toBe(false)
    expect(store.assignError).toBe('A developer cannot unassign a credential.')
  })

  it('loads again on credential events and a resync, once a project is shown', async () => {
    const seen = stubEngine(list)
    const store = useFlavorCredentialsStore()
    stops.push(store.follow())
    const feed = openEventFeed()

    feed.send('credential.assigned')
    await flushPromises()
    expect(seen).toHaveLength(0)

    await store.open('prj_1')
    feed.send('job.state_changed')
    feed.send('credential.assigned')
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(3)
  })
})
