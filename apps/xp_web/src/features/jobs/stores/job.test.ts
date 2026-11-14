import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine } from '@/testing/fetch'
import { jobOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useJobStore } from './job'

describe('useJobStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function engine() {
    return stubEngine({
      'GET /jobs/job_2': { status: 200, body: jobOf() },
      'GET /jobs/job_3': { status: 200, body: jobOf({ id: 'job_3', state: 'interrupted' }) },
      'GET /jobs/job_4': { status: 404, body: errorBody('not_found', 'No job.') },
      'GET /jobs/job_5': { status: 500, body: errorBody('internal', 'Broken.') },
      'POST /jobs/job_2/cancel': { status: 200, body: jobOf({ state: 'cancelled' }) },
      'POST /jobs/job_3/resume': { status: 202, body: jobOf({ id: 'job_3', state: 'queued' }) },
      'POST /jobs/job_5/cancel': { status: 409, body: errorBody('conflict', 'It ended.') },
    })
  }

  it('shows the job, and what can be done with it', async () => {
    engine()
    const store = useJobStore()

    await store.open('job_2')
    expect(store.cancellable).toBe(true)
    expect(store.resumable).toBe(false)

    await store.open('job_3')
    expect(store.resumable).toBe(true)
  })

  it('knows a job that is not there, and says why one could not be read', async () => {
    engine()
    const store = useJobStore()
    expect(store.cancellable).toBe(false)

    await store.open('job_4')
    expect(store.missing).toBe(true)

    await store.open('job_5')
    expect(store.error).toBe('Broken.')
  })

  it('drops an answer for a job it no longer shows', async () => {
    engine()
    const store = useJobStore()

    const failing = store.open('job_5')
    const ok = store.open('job_2')
    await failing
    await ok
    expect(store.error).toBeNull()

    const stale = store.open('job_3')
    await store.open('job_4')
    await stale
    expect(store.job).toBeNull()
  })

  it('cancels and resumes', async () => {
    const seen = engine()
    const store = useJobStore()
    await store.open('job_2')

    const cancelling = store.act('cancel')
    expect(await store.act('resume')).toBe(false)
    expect(await cancelling).toBe(true)
    expect(store.job?.state).toBe('cancelled')

    await store.open('job_3')
    expect(await store.act('resume')).toBe(true)
    expect(store.job?.state).toBe('queued')
    expect(seen.at(-1)?.body).toEqual({})
  })

  it('says why the engine refused', async () => {
    stubEngine({
      'GET /jobs/job_5': { status: 200, body: jobOf({ id: 'job_5' }) },
      'POST /jobs/job_5/cancel': { status: 409, body: errorBody('conflict', 'It ended.') },
    })
    const store = useJobStore()
    await store.open('job_5')

    expect(await store.act('cancel')).toBe(false)
    expect(store.error).toBe('It ended.')
  })

  it('does nothing before it shows a job', async () => {
    expect(await useJobStore().act('cancel')).toBe(false)
  })

  it('follows its own events', async () => {
    const seen = engine()
    const store = useJobStore()
    await store.open('job_2')
    stops.push(store.follow())
    const feed = openEventFeed()
    seen.length = 0

    feed.send('job.step_changed', { jobId: 'job_9' })
    feed.send('run.dispatched', { jobId: 'job_2' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('job.step_changed', { jobId: 'job_2' })
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(2)
  })
})
