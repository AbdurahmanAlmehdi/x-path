import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { flavorCredentialOf, namedCredentialOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useFlavorCredentialsStore } from './flavorCredentials'

describe('useFlavorCredentialsStore', () => {
  const stops: Array<() => void> = []
  const dev = { app: '.', appName: 'app', flavor: 'dev', hasIos: false }
  const prod = { app: '.', appName: 'app', flavor: 'prod', hasIos: true }

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

  describe('creating a distribution certificate', () => {
    const path = 'POST /projects/prj_1/flavors/prod/distribution-certificate'
    const identity = flavorCredentialOf({ id: 'crd_9', name: 'Linux signing', flavor: 'prod', kind: 'apple_distribution' })

    it('asks the engine for the flavor, trims the name, and loads the identity it assigned', async () => {
      let created = false
      const seen = stubEngine({
        'GET /projects/prj_1/credentials': () => ({
          status: 200,
          body: { credentials: created ? [identity] : [] },
        }),
        [path]: () => {
          created = true
          return { status: 201, body: namedCredentialOf({ id: 'crd_9', kind: 'apple_distribution' }) }
        },
      })
      const store = useFlavorCredentialsStore()
      expect(await store.createCertificate(prod, 'Linux signing')).toBe(false)
      expect(seen).toHaveLength(0)

      await store.open('prj_1')
      const creating = store.createCertificate(prod, '  Linux signing ')
      expect(store.creating).toBe(true)

      expect(await creating).toBe(true)
      const post = seen.find((request) => request.method === 'POST')
      expect(post?.search).toBe('?app=.')
      expect(post?.body).toEqual({ name: 'Linux signing' })
      expect(store.creating).toBe(false)
      expect(store.of(prod).map((credential) => credential.name)).toEqual(['Linux signing'])
      expect(store.certificateError).toBeNull()
    })

    it("lists the team's certificates at Apple's limit", async () => {
      stubEngine({
        ...list,
        [path]: {
          status: 409,
          body: {
            error: {
              code: 'conflict',
              message: "The team has 3 distribution certificates, Apple's limit is 3.",
              hint: 'Revoke one in App Store Connect.',
              details: {
                reason: 'certificate_limit',
                limit: 3,
                certificates: [
                  { id: 'a', serialNumber: '0A', name: 'Apple Distribution: Acme', expirationDate: '2027-01-02T00:00:00Z' },
                  { id: 'b', serialNumber: '0B' },
                ],
              },
            },
          },
        },
      })
      const store = useFlavorCredentialsStore()
      await store.open('prj_1')

      expect(await store.createCertificate(prod, 'Another')).toBe(false)

      expect(store.certificateLimit).toEqual({
        limit: 3,
        certificates: [
          { id: 'a', serialNumber: '0A', name: 'Apple Distribution: Acme', expirationDate: '2027-01-02T00:00:00Z' },
          { id: 'b', serialNumber: '0B' },
        ],
      })
      expect(store.certificateError).toBe(
        "The team has 3 distribution certificates, Apple's limit is 3. Revoke one in App Store Connect.",
      )
      store.resetCertificate()
      expect(store.certificateLimit).toBeNull()
      expect(store.certificateError).toBeNull()
    })

    it('says what the engine said for any other refusal, and when it did not answer', async () => {
      stubEngine({
        ...list,
        [path]: {
          status: 400,
          body: errorBody('invalid_request', 'The flavor prod has no App Store Connect API key.'),
        },
      })
      const store = useFlavorCredentialsStore()
      await store.open('prj_1')

      expect(await store.createCertificate(prod, 'Linux signing')).toBe(false)
      expect(store.certificateLimit).toBeNull()
      expect(store.certificateError).toBe('The flavor prod has no App Store Connect API key.')

      stubEngine({
        [path]: {
          status: 409,
          body: { error: { code: 'conflict', message: 'At the limit.', details: { reason: 'certificate_limit', limit: 3 } } },
        },
      })
      expect(await store.createCertificate(prod, 'Linux signing')).toBe(false)
      expect(store.certificateLimit).toEqual({ limit: 3, certificates: [] })

      stubUnreachableEngine()
      expect(await store.createCertificate(prod, 'Linux signing')).toBe(false)
      expect(store.certificateLimit).toBeNull()
      expect(store.certificateError).toBe('The engine did not answer. Check that it is running.')
      expect(store.creating).toBe(false)
    })
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
