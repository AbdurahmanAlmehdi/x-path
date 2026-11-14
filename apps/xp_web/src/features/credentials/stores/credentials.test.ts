import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { namedCredentialOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useCredentialsStore } from './credentials'

describe('useCredentialsStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  const list = { 'GET /credentials': { status: 200, body: { credentials: [namedCredentialOf()] } } }

  it('loads the credentials', async () => {
    stubEngine(list)
    const store = useCredentialsStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.credentials.map((credential) => credential.name)).toEqual(['Upload keystore'])
  })

  it('says why the credentials could not be read', async () => {
    stubUnreachableEngine()
    const store = useCredentialsStore()

    await store.load()

    expect(store.error).toBe('The engine did not answer. Check that it is running.')
  })

  it('sends a new credential to the engine, keeps no secret and loads again', async () => {
    const seen = stubEngine({ ...list, 'POST /credentials': { status: 201, body: namedCredentialOf() } })
    const store = useCredentialsStore()

    const saved = await store.create({
      name: 'Upload keystore',
      kind: 'keystore',
      keystore: 'RkFLRQ==',
      storePassword: 'fake-store-password',
      keyAlias: 'upload',
    })

    expect(saved).toBe(true)
    expect(seen[0]?.body).toMatchObject({ kind: 'keystore', keystore: 'RkFLRQ==' })
    expect(store.notice).toBe('Credential saved')
    expect(store.command).toBeNull()
    expect(JSON.stringify(store.$state)).not.toContain('fake-store-password')
    expect(JSON.stringify(store.$state)).not.toContain('RkFLRQ==')
  })

  it('says why the engine refused a credential', async () => {
    stubEngine({
      'POST /credentials': {
        status: 422,
        body: errorBody('credential_rejected', 'keytool could not open the keystore.', 'Check the store password.'),
      },
    })
    const store = useCredentialsStore()

    expect(await store.create({ name: 'k', kind: 'shorebird', token: 'sb_api_fake' })).toBe(false)
    expect(store.commandError).toBe('keytool could not open the keystore. Check the store password.')
  })

  it('replaces a secret, renames, checks and deletes', async () => {
    const seen = stubEngine({
      ...list,
      'PUT /credentials/crd_1': { status: 200, body: namedCredentialOf() },
      'PATCH /credentials/crd_1': { status: 200, body: namedCredentialOf({ name: 'Play upload key' }) },
      'POST /credentials/crd_1/verify': { status: 200, body: namedCredentialOf({ status: 'rejected' }) },
      'DELETE /credentials/crd_1': { status: 204 },
    })
    const store = useCredentialsStore()

    expect(await store.replace('crd_1', { kind: 'shorebird', token: 'sb_api_fake' })).toBe(true)
    expect(await store.rename('crd_1', ' Play upload key ')).toBe(true)
    expect(store.notice).toBe('Renamed to Play upload key')
    expect(await store.verify('crd_1')).toBe(true)
    expect(store.notice).toBe('Checked Upload keystore: Rejected')
    expect(await store.remove('crd_1', true)).toBe(true)
    expect(await store.remove('crd_1', false)).toBe(true)
    expect(store.notice).toBe('Credential deleted')

    const changes = seen.filter((request) => request.method !== 'GET')
    expect(changes.map((request) => `${request.method} ${request.path}${request.search}`)).toEqual([
      'PUT /credentials/crd_1',
      'PATCH /credentials/crd_1',
      'POST /credentials/crd_1/verify',
      'DELETE /credentials/crd_1?force=true',
      'DELETE /credentials/crd_1',
    ])
    expect(changes[1]?.body).toEqual({ name: 'Play upload key' })
  })

  it('loads again on credential events and a resync, not on others', async () => {
    const seen = stubEngine({ 'GET /credentials': { status: 200, body: { credentials: [] } } })
    const store = useCredentialsStore()
    stops.push(store.follow())
    const feed = openEventFeed()

    feed.send('runner.connected')
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('credential.saved', { credentialId: 'crd_1' })
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(2)
  })
})
