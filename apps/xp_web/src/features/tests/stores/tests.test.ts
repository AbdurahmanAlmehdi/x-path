import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { type Answer, errorBody, stubEngine } from '@/testing/fetch'
import { baselineOf, jobOf, testRunOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useTestsStore } from './tests'

describe('useTestsStore', () => {
  const stops: Array<() => void> = []
  const testedJob = jobOf({
    steps: [
      { ordinal: 0, kind: 'test', state: 'succeeded', sideEffect: false, attempts: 1, startedAt: '2026-11-14T09:00:00Z', finishedAt: '2026-11-14T09:00:42Z' },
    ],
  })

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function engine(routes: Record<string, Answer | (() => Answer)> = {}) {
    return stubEngine({
      'GET /projects/prj_1/tests/baseline': {
        status: 200,
        body: {
          baselines: [
            baselineOf({ branch: 'develop', jobId: 'job_0', createdAt: '2026-11-12T09:00:00Z' }),
            baselineOf(),
          ],
        },
      },
      'GET /jobs/job_1/tests': { status: 200, body: testRunOf({ id: 'tr_1', jobId: 'job_1', baseline: true, diff: { newFailures: [], fixed: [], missing: [], stillFailing: 1 } }) },
      'GET /jobs/job_2/tests': { status: 200, body: testRunOf() },
      'GET /jobs/job_2': { status: 200, body: testedJob },
      ...routes,
    })
  }

  it('shows the newest baseline, with the runs on offer', async () => {
    engine()
    const store = useTestsStore()

    await store.open('prj_1')

    expect(store.loaded).toBe(true)
    expect(store.shownJobId).toBe('job_1')
    expect(store.run?.run.id).toBe('tr_1')
    expect(store.comparedBaseline).toBeUndefined()
    expect(store.runs.map((run) => [run.jobId, run.baseline])).toEqual([
      ['job_1', true],
      ['job_0', true],
    ])
    // Its job is not on the engine: no duration.
    expect(store.duration).toBeNull()
  })

  it('shows the run a job page opened, compared with its baseline, with how long the tests ran', async () => {
    engine()
    const store = useTestsStore()

    await store.open('prj_1', 'job_2')

    expect(store.shownJobId).toBe('job_2')
    expect(store.run?.run.diff.newFailures).toHaveLength(1)
    expect(store.comparedBaseline?.jobId).toBe('job_1')
    expect(store.duration).toBe(42_000)
    expect(store.runs[0]).toEqual({
      jobId: 'job_2',
      branch: 'main',
      appPath: '.',
      createdAt: '2026-11-14T09:00:00Z',
      baseline: false,
    })

    store.select('job_1')
    await flushPromises()
    expect(store.run?.run.id).toBe('tr_1')
    expect(store.job).toBeNull()
    expect(store.runs.map((run) => run.jobId)).toEqual(['job_1', 'job_2', 'job_0'])
  })

  it('says why the baselines or a run could not be read', async () => {
    engine({
      'GET /projects/prj_1/tests/baseline': { status: 500, body: errorBody('internal', 'Broken.') },
      'GET /jobs/job_3/tests': { status: 404, body: errorBody('not_found', 'No test run.') },
    })
    const store = useTestsStore()

    await store.open('prj_1', 'job_3')

    expect(store.error).toBe('Broken.')
    expect(store.runError).toBe('No test run.')
    expect(store.run).toBeNull()
    expect(store.runs.map((run) => run.jobId)).toEqual(['job_3'])
  })

  it('shows nothing for a project without runs', async () => {
    engine({ 'GET /projects/prj_1/tests/baseline': { status: 200, body: { baselines: [] } } })
    const store = useTestsStore()

    await store.open('prj_1')

    expect(store.shownJobId).toBeNull()
    expect(store.runs).toEqual([])
  })

  it('drops the answers for a project or run it no longer shows', async () => {
    engine({
      'GET /projects/prj_2/tests/baseline': { status: 500 },
    })
    const store = useTestsStore()

    const first = store.open('prj_1', 'job_2')
    store.select('job_1')
    const second = store.open('prj_2')
    await Promise.all([first, second])
    await flushPromises()

    expect(store.projectId).toBe('prj_2')
    expect(store.baselines).toEqual([])
    expect(store.error).toBe('The engine answered 500.')
  })

  it('drops a failure of a run it no longer shows', async () => {
    engine({ 'GET /jobs/job_3/tests': { status: 500 } })
    const store = useTestsStore()

    const first = store.open('prj_1', 'job_3')
    store.select('job_2')
    await first
    await flushPromises()

    expect(store.runError).toBeNull()
    expect(store.run?.run.id).toBe('tr_2')
  })

  it('offers the runs that end while it is open, and shows the latest', async () => {
    const seen = engine()
    const store = useTestsStore()
    await store.open('prj_1')
    stops.push(store.follow())
    const feed = openEventFeed()
    seen.length = 0

    feed.send('test_run.completed', { projectId: 'prj_2', jobId: 'job_9' })
    feed.send('job.state_changed', { projectId: 'prj_1', jobId: 'job_2' })
    feed.send('test_run.completed', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('test_run.completed', { projectId: 'prj_1', jobId: 'job_2', branch: 'main', baseline: false })
    await flushPromises()
    expect(store.shownJobId).toBe('job_2')
    expect(store.run?.run.id).toBe('tr_2')
    expect(seen.map((request) => request.path)).toEqual(['/jobs/job_2/tests', '/jobs/job_2'])

    seen.length = 0
    feed.send('test_run.completed', { projectId: 'prj_1', jobId: 'job_2', branch: 'main', baseline: true })
    await flushPromises()
    expect(seen.map((request) => request.path)).toEqual([
      '/projects/prj_1/tests/baseline',
      '/jobs/job_2/tests',
      '/jobs/job_2',
    ])
    expect(store.completed).toHaveLength(1)

    seen.length = 0
    feed.resync()
    await flushPromises()
    expect(seen.map((request) => request.path)).toEqual([
      '/projects/prj_1/tests/baseline',
      '/jobs/job_2/tests',
      '/jobs/job_2',
    ])
  })

  it('follows nothing before it shows a project', async () => {
    const seen = engine()
    const store = useTestsStore()
    stops.push(store.follow())
    openEventFeed().resync()
    await flushPromises()
    expect(seen).toHaveLength(0)
  })
})
