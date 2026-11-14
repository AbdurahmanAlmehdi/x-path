import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { type Answer, errorBody, stubEngine } from '@/testing/fetch'
import { approvalOf, releaseOf, runOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useReleasesStore } from './releases'

describe('useReleasesStore', () => {
  const stops: Array<() => void> = []
  const live = releaseOf()
  const building = releaseOf({ id: 'rel_2', version: '1.2.0', state: 'building', headSha: undefined })
  const notes = {
    releaseId: 'rel_1',
    version: '1.1.0',
    build: 6,
    to: 'abcdef0',
    commits: 2,
    groups: [],
    slack: 'slack',
    whatsapp: 'whatsapp',
  }
  const credential = {
    id: 'cred_1',
    projectId: 'prj_1',
    app: '.',
    flavor: 'prod',
    kind: 'asc_key',
    status: 'verified',
  }

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function engine(routes: Record<string, Answer | (() => Answer)> = {}) {
    return stubEngine({
      'GET /releases': { status: 200, body: { releases: [building, live] } },
      'GET /approvals': { status: 200, body: { approvals: [approvalOf()] } },
      'GET /projects/prj_1/credentials': { status: 200, body: { credentials: [credential] } },
      'GET /releases/rel_1/history': { status: 200, body: { events: [{ kind: 'created', at: '2026-11-10T09:00:00Z' }] } },
      'GET /releases/rel_2/history': { status: 200, body: { events: [] } },
      'GET /releases/rel_1/notes': { status: 200, body: notes },
      ...routes,
    })
  }

  it('shows the release in flight, with the approvals and credentials of the project', async () => {
    const seen = engine()
    const store = useReleasesStore()

    await store.open('prj_1')

    expect(store.loaded).toBe(true)
    expect(store.release?.id).toBe('rel_2')
    expect(store.approvals).toHaveLength(1)
    expect(store.readsStore(live, 'apple')).toBe(true)
    expect(store.readsStore(live, 'play')).toBe(false)
    expect(store.history).toEqual([])
    // A release without a commit has no notes yet.
    expect(seen.some((request) => request.path.endsWith('/notes'))).toBe(false)
    expect(seen.find((request) => request.path === '/releases')?.search).toBe('?project=prj_1')
  })

  it('shows a picked release with its history and notes, and the newest when none is in flight', async () => {
    engine({ 'GET /releases': { status: 200, body: { releases: [live, releaseOf({ id: 'rel_0' })] } } })
    const store = useReleasesStore()

    await store.open('prj_1')
    expect(store.release?.id).toBe('rel_1')
    expect(store.history).toHaveLength(1)
    expect(store.notes?.commits).toBe(2)

    store.select('rel_0')
    expect(store.release?.id).toBe('rel_0')
    expect(store.history).toEqual([])
    await flushPromises()
    expect(store.notes).toBeNull()
    expect(store.notesError).toBe('The engine answered 404.')
  })

  it('goes without what it cannot read, and says why the releases could not be read', async () => {
    engine({
      'GET /approvals': { status: 500 },
      'GET /projects/prj_1/credentials': { status: 500 },
      'GET /releases': { status: 200, body: { releases: [live] } },
      'GET /releases/rel_1/history': { status: 500 },
    })
    const store = useReleasesStore()
    await store.open('prj_1')
    expect(store.release?.id).toBe('rel_1')
    expect(store.approvals).toEqual([])
    expect(store.readsStore(live, 'apple')).toBe(false)
    expect(store.history).toEqual([])

    setActivePinia(createPinia())
    engine({ 'GET /releases': { status: 500, body: errorBody('internal', 'Broken.') } })
    const broken = useReleasesStore()
    await broken.open('prj_1')
    expect(broken.error).toBe('Broken.')
    expect(broken.release).toBeNull()
  })

  it('drops the answers for a project or release it no longer shows', async () => {
    engine({
      'GET /releases': () => ({ status: 200, body: { releases: [live] } }),
    })
    const store = useReleasesStore()

    const first = store.open('prj_1')
    const second = store.open('prj_2')
    await Promise.all([first, second])
    expect(store.projectId).toBe('prj_2')

    setActivePinia(createPinia())
    engine({ 'GET /releases': { status: 500 } })
    const failing = useReleasesStore()
    const one = failing.open('prj_1')
    const two = failing.open('prj_2')
    await Promise.all([one, two])
    expect(failing.error).toBe('The engine answered 500.')
  })

  it('follows the release, approval and credential events of its project', async () => {
    const seen = engine()
    const store = useReleasesStore()
    await store.open('prj_1')
    stops.push(store.follow())
    const feed = openEventFeed()
    seen.length = 0

    feed.send('release.state_changed', { projectId: 'prj_2' })
    feed.send('run.dispatched', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('release.store_changed', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen.map((request) => request.path)).toEqual(['/releases', '/releases/rel_2/history'])

    seen.length = 0
    feed.send('approval.decided', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen.map((request) => request.path)).toEqual(['/approvals', '/releases/rel_2/history'])

    seen.length = 0
    feed.send('credential.assigned', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen.map((request) => request.path)).toEqual(['/projects/prj_1/credentials'])

    seen.length = 0
    feed.resync()
    await flushPromises()
    expect(new Set(seen.map((request) => request.path))).toEqual(
      new Set(['/releases', '/approvals', '/projects/prj_1/credentials', '/releases/rel_2/history']),
    )
  })

  it('follows nothing before it shows a project', async () => {
    const seen = engine()
    const store = useReleasesStore()
    stops.push(store.follow())
    openEventFeed().resync()
    await flushPromises()
    expect(seen).toHaveLength(0)
  })

  it('sends each command for the release shown, and says what it did', async () => {
    const seen = engine({
      'GET /releases': { status: 200, body: { releases: [live] } },
      'POST /releases/rel_1/refresh': { status: 200, body: live },
      'POST /releases/rel_1/stores/apple/status': { status: 200, body: live },
      'POST /releases/rel_1/merge': { status: 202, body: runOf({ id: 'run_8' }) },
      'POST /releases/rel_1/rollout': { status: 202, body: runOf({ id: 'run_9' }) },
      'POST /releases/rel_1/builds': { status: 202, body: runOf({ id: 'run_10' }) },
      'PUT /releases/rel_1/texts': { status: 200, body: live },
      'POST /releases/rel_1/patches/2/promote': { status: 202, body: runOf({ id: 'run_11' }) },
    })
    const store = useReleasesStore()
    await store.open('prj_1')

    expect(await store.refresh()).toMatchObject({ id: 'rel_1' })
    expect(store.notice).toBeNull()

    const marking = store.mark('apple', 'live')
    expect(store.command).toBe('marking')
    expect(await store.merge()).toBeNull()
    await marking
    expect(store.notice).toBe('Store status saved')
    expect(seen.find((request) => request.path.endsWith('/status'))?.body).toEqual({ state: 'live' })

    expect((await store.merge())?.id).toBe('run_8')
    expect(store.notice).toBe('Merge requested: approve it to merge')
    expect((await store.rollout({ store: 'play', action: 'fraction', userFraction: 0.2 }))?.id).toBe('run_9')
    expect(seen.find((request) => request.path.endsWith('/rollout'))?.body).toEqual({
      store: 'play',
      action: 'fraction',
      userFraction: 0.2,
    })
    expect((await store.newBuild())?.id).toBe('run_10')
    await store.saveTexts({ whatsNew: 'New.', whatToTest: '' })
    expect(store.notice).toBe('Store texts saved')
    expect((await store.movePatch(2, 'promote'))?.id).toBe('run_11')
    expect(store.notice).toBe('Patch change requested: approve it to apply')
    expect(store.command).toBeNull()

    store.select(null)
    expect(store.notice).toBeNull()
  })

  it('says why the engine refused a command, and sends nothing without a release', async () => {
    engine({
      'GET /releases': { status: 200, body: { releases: [live] } },
      'POST /releases/rel_1/merge': { status: 409, body: errorBody('conflict', 'Not live everywhere.') },
    })
    const store = useReleasesStore()
    expect(await store.refresh()).toBeNull()

    await store.open('prj_1')
    expect(await store.merge()).toBeNull()
    expect(store.commandError).toBe('Not live everywhere.')
    expect(store.notice).toBeNull()
  })
})
