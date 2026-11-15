import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine } from '@/testing/fetch'
import { runOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useRunStore } from './run'

describe('useRunStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function engine() {
    return stubEngine({
      'GET /runs/run_1': { status: 200, body: runOf() },
      'GET /runs/run_2': { status: 404, body: errorBody('not_found', 'No run.') },
      'GET /runs/run_3': { status: 500, body: errorBody('internal', 'Broken.') },
      'POST /runs/run_1/cancel': { status: 200, body: runOf({ state: 'cancelled' }) },
      'POST /runs/run_1/run-again': { status: 202, body: runOf({ id: 'run_9' }) },
      'POST /runs/run_1/rerun-failed': { status: 409, body: errorBody('conflict', 'Nothing failed.') },
    })
  }

  it('shows the run, and what can be done with it', async () => {
    engine()
    const store = useRunStore()

    await store.open('run_1')

    expect(store.run?.id).toBe('run_1')
    expect(store.cancellable).toBe(true)
    expect(store.rerunnable).toBe(false)
  })

  it('offers a re-run of failed jobs, and no cancel once every job ended', async () => {
    stubEngine({
      'GET /runs/run_1': {
        status: 200,
        body: runOf({
          state: 'failed',
          jobs: [{ id: 'job_1', name: 'build', stage: 0, state: 'failed' }],
        }),
      },
    })
    const store = useRunStore()

    await store.open('run_1')

    expect(store.cancellable).toBe(false)
    expect(store.rerunnable).toBe(true)
  })

  it('knows a run that is not there, and says why one could not be read', async () => {
    engine()
    const store = useRunStore()

    await store.open('run_2')
    expect(store.missing).toBe(true)
    expect(store.cancellable).toBe(false)
    expect(store.rerunnable).toBe(false)

    await store.open('run_3')
    expect(store.missing).toBe(false)
    expect(store.error).toBe('Broken.')
  })

  it('drops an answer for a run it no longer shows', async () => {
    engine()
    const store = useRunStore()

    const first = store.open('run_3')
    const second = store.open('run_2')
    await first
    await second
    expect(store.error).toBeNull()

    const third = store.open('run_1')
    await store.open('run_2')
    await third
    expect(store.run).toBeNull()
  })

  it('cancels the run', async () => {
    const seen = engine()
    const store = useRunStore()
    await store.open('run_1')

    const answer = store.act('cancel')
    expect(store.busy).toBe('cancel')
    expect(await store.act('runAgain')).toBeNull()
    await answer

    expect(store.run?.state).toBe('cancelled')
    expect(store.busy).toBeNull()
    expect(seen.filter((request) => request.method === 'POST')).toHaveLength(1)
  })

  it('runs again, keeping the run it shows', async () => {
    engine()
    const store = useRunStore()
    await store.open('run_1')

    const run = await store.act('runAgain')

    expect(run?.id).toBe('run_9')
    expect(store.run?.id).toBe('run_1')
  })

  it('says why the engine refused', async () => {
    engine()
    const store = useRunStore()
    await store.open('run_1')

    expect(await store.act('rerunFailed')).toBeNull()
    expect(store.error).toBe('Nothing failed.')
  })

  it('does nothing before it shows a run', async () => {
    expect(await useRunStore().act('cancel')).toBeNull()
  })

  it('follows the job and approval events of its project', async () => {
    const seen = engine()
    const store = useRunStore()
    await store.open('run_1')
    stops.push(store.follow())
    const feed = openEventFeed()
    seen.length = 0

    feed.send('run.dispatched', { projectId: 'prj_1' })
    feed.send('job.state_changed', { projectId: 'prj_2' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('job.state_changed', { projectId: 'prj_1' })
    await flushPromises()
    feed.send('approval.decided', { projectId: 'prj_1' })
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(3)
  })
})
