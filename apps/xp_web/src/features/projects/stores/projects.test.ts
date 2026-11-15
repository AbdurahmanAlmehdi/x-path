import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { projectOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useProjectsStore } from './projects'

describe('useProjectsStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  it('loads the projects', async () => {
    stubEngine({ 'GET /projects': { status: 200, body: { projects: [projectOf()] } } })
    const store = useProjectsStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.projects.map((project) => project.fullName)).toEqual(['acme/app'])
    expect(store.error).toBeNull()
  })

  it('names a project in full or short, and by its id while unknown', async () => {
    stubEngine({ 'GET /projects': { status: 200, body: { projects: [projectOf()] } } })
    const store = useProjectsStore()
    expect(store.nameOf('prj_1')).toBe('prj_1')

    await store.load()

    expect(store.nameOf('prj_1')).toBe('acme/app')
    expect(store.nameOf('prj_1', { short: true })).toBe('app')
    expect(store.nameOf('prj_9', { short: true })).toBe('prj_9')
  })

  it('says why the projects could not be read', async () => {
    stubEngine({ 'GET /projects': { status: 500, body: errorBody('internal', 'Broken.') } })
    const store = useProjectsStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.error).toBe('Broken.')
  })

  it('says when the engine does not answer', async () => {
    stubUnreachableEngine()
    const store = useProjectsStore()

    await store.load()

    expect(store.error).toBe('The engine did not answer. Check that it is running.')
  })

  it('loads again on project events and a resync, not on others', async () => {
    const seen = stubEngine({ 'GET /projects': { status: 200, body: { projects: [] } } })
    const store = useProjectsStore()
    stops.push(store.follow())
    const feed = openEventFeed()

    feed.send('job.state_changed', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('project.added', { projectId: 'prj_2' })
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(2)
  })
})
