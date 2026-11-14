import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { stubEngine } from '@/testing/fetch'
import { workflowSummaryOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { useWorkflowsStore } from './workflows'

describe('useWorkflowsStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function engine() {
    return stubEngine({
      'GET /projects/prj_1/workflows': {
        status: 200,
        body: {
          workflows: [workflowSummaryOf(), workflowSummaryOf({ id: 'wf_2', name: 'count', title: undefined })],
        },
      },
      'GET /projects/prj_2/workflows': { status: 404 },
    })
  }

  it('names workflows by title, then name, then id', async () => {
    engine()
    const store = useWorkflowsStore()

    await store.know(['prj_1', 'prj_1'])

    expect(store.name('wf_1')).toBe('Dev build')
    expect(store.name('wf_2')).toBe('count')
    expect(store.name('wf_9')).toBe('wf_9')
  })

  it('asks for the workflows of a project once', async () => {
    const seen = engine()
    const store = useWorkflowsStore()

    await store.ofProject('prj_1')
    await store.ofProject('prj_1')

    expect(seen).toHaveLength(1)
  })

  it('asks again after a failure, and leaves the ids meanwhile', async () => {
    const seen = engine()
    const store = useWorkflowsStore()

    await store.know(['prj_2'])
    await store.know(['prj_2'])

    expect(seen).toHaveLength(2)
    expect(store.name('wf_1')).toBe('wf_1')
  })

  it('asks again when the workflows of a project change, or on a resync', async () => {
    const seen = engine()
    const store = useWorkflowsStore()
    await store.know(['prj_1'])
    stops.push(store.follow())
    const feed = openEventFeed()

    feed.send('workflow.saved', { projectId: 'prj_1', workflowId: 'wf_3' })
    feed.send('workflow.saved', {})
    feed.send('run.dispatched', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen).toHaveLength(2)

    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(3)
  })
})
