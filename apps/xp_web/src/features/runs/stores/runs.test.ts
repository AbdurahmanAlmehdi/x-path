import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine } from '@/testing/fetch'
import { runOf, workflowSummaryOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { runsPageSize, useRunsStore } from './runs'

describe('useRunsStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function engine(runs = [runOf()], next?: string) {
    return stubEngine({
      'GET /runs': () => ({ status: 200, body: { runs, next } }),
      'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [workflowSummaryOf()] } },
    })
  }

  it('loads the runs the filter asks for, and the names of their workflows', async () => {
    const seen = engine()
    const store = useRunsStore()

    await store.load({ project: 'prj_1', workflow: 'wf_1', state: 'running' })
    await flushPromises()

    expect(store.loaded).toBe(true)
    expect(store.runs).toHaveLength(1)
    expect(store.next).toBeNull()
    expect(seen[0]?.search).toBe(`?project=prj_1&workflow=wf_1&state=running&limit=${runsPageSize}`)
    expect(seen.map((request) => request.path)).toContain('/projects/prj_1/workflows')
  })

  it('adds the next page', async () => {
    const seen = engine([runOf()], 'run_1')
    const store = useRunsStore()
    await store.load({})

    engine([runOf({ id: 'run_0' })])
    const more = store.more()
    expect(store.loadingMore).toBe(true)
    await more

    expect(store.runs.map((run) => run.id)).toEqual(['run_1', 'run_0'])
    expect(store.next).toBeNull()
    expect(store.loadingMore).toBe(false)
    expect(seen[0]?.search).toBe(`?limit=${runsPageSize}`)
  })

  it('has no next page to add without a next', async () => {
    const seen = engine()
    const store = useRunsStore()
    await store.load({})

    await store.more()

    expect(seen.filter((request) => request.path === '/runs')).toHaveLength(1)
  })

  it('says why the runs could not be read', async () => {
    stubEngine({ 'GET /runs': { status: 400, body: errorBody('invalid_request', 'Bad filter.') } })
    const store = useRunsStore()

    await store.load({ state: 'running' })

    expect(store.loaded).toBe(true)
    expect(store.error).toBe('Bad filter.')
  })

  it('says why the next page could not be read', async () => {
    engine([runOf()], 'run_1')
    const store = useRunsStore()
    await store.load({})

    stubEngine({ 'GET /runs': { status: 500, body: errorBody('internal', 'Broken.') } })
    await store.more()

    expect(store.error).toBe('Broken.')
    expect(store.runs).toHaveLength(1)
  })

  it('drops the answers of a filter it no longer shows', async () => {
    engine([runOf()], 'run_1')
    const store = useRunsStore()
    const first = store.load({ state: 'failed' })
    const second = store.load({ state: 'running' })
    await first
    await second
    expect(store.filter).toEqual({ state: 'running' })

    stubEngine({ 'GET /runs': { status: 500, body: errorBody('internal', 'Broken.') } })
    const stale = store.load({ state: 'failed' })
    engine()
    await store.load({ state: 'queued' })
    await stale
    expect(store.error).toBeNull()

    engine([runOf({ id: 'run_9' })], 'run_9')
    await store.load({})
    engine([runOf({ id: 'run_8' })])
    const more = store.more()
    engine([])
    await store.load({ state: 'cancelled' })
    await more
    expect(store.runs).toEqual([])
  })

  it('loads again when a run of its project is dispatched or a job changes', async () => {
    const seen = engine()
    const store = useRunsStore()
    await store.load({ project: 'prj_1' })
    await flushPromises()
    stops.push(store.follow())
    const feed = openEventFeed()
    seen.length = 0

    feed.send('run.dispatched', { projectId: 'prj_2' })
    feed.send('approval.requested', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('job.state_changed', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen.filter((request) => request.path === '/runs')).toHaveLength(1)
  })

  it('loads again on any run of every project, and on a resync', async () => {
    const seen = engine()
    const store = useRunsStore()
    await store.load({})
    stops.push(store.follow())
    const feed = openEventFeed()
    seen.length = 0

    feed.send('run.dispatched', { projectId: 'prj_2' })
    await flushPromises()
    feed.resync()
    await flushPromises()

    expect(seen.filter((request) => request.path === '/runs')).toHaveLength(2)
  })
})
