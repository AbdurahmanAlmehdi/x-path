import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine } from '@/testing/fetch'
import { projectOf, runOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { recentRunCount, useProjectStore } from './project'

describe('useProjectStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function engine() {
    return stubEngine({
      'GET /projects/prj_1': { status: 200, body: projectOf() },
      'GET /projects/prj_1/runs': {
        status: 200,
        body: { runs: [runOf(), runOf({ id: 'run_2', state: 'succeeded' })] },
      },
      'GET /projects/prj_2': { status: 404, body: errorBody('not_found', 'No project.') },
      'GET /projects/prj_3': { status: 500, body: errorBody('internal', 'Broken.') },
      'GET /projects/prj_3/runs': { status: 500 },
    })
  }

  it('shows the project with its newest runs', async () => {
    const seen = engine()
    const store = useProjectStore()

    await store.open('prj_1')

    expect(store.project?.fullName).toBe('acme/app')
    expect(store.runs).toHaveLength(2)
    expect(store.running).toBe(1)
    expect(seen.find((request) => request.path.endsWith('/runs'))?.search).toBe(
      `?limit=${recentRunCount}`,
    )
  })

  it('knows a project that is gone', async () => {
    engine()
    const store = useProjectStore()

    await store.open('prj_2')

    expect(store.missing).toBe(true)
    expect(store.error).toBeNull()
  })

  it('says why the project could not be read', async () => {
    engine()
    const store = useProjectStore()

    await store.open('prj_3')

    expect(store.missing).toBe(false)
    expect(store.error).toBe('Broken.')
    expect(store.runs).toEqual([])
  })

  it('drops an answer for a project it no longer shows', async () => {
    engine()
    const store = useProjectStore()

    const first = store.open('prj_3')
    await store.open('prj_1')
    await first

    expect(store.error).toBeNull()
    expect(store.project?.id).toBe('prj_1')
  })

  it('keeps what it shows when the same project opens again', async () => {
    engine()
    const store = useProjectStore()
    await store.open('prj_1')

    const again = store.open('prj_1')
    expect(store.project?.id).toBe('prj_1')
    await again
  })

  it('follows the events of its project', async () => {
    const seen = engine()
    const store = useProjectStore()
    await store.open('prj_1')
    seen.length = 0
    stops.push(store.follow())
    const feed = openEventFeed()

    feed.send('project.scanned', { projectId: 'prj_1' })
    feed.send('job.state_changed', { projectId: 'prj_1' })
    feed.send('run.dispatched', { projectId: 'prj_9' })
    feed.send('approval.requested', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen.map((request) => request.path)).toEqual(['/projects/prj_1', '/projects/prj_1/runs'])

    seen.length = 0
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(2)
  })
})
