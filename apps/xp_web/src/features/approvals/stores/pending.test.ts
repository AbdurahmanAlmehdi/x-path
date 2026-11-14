import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine } from '@/testing/fetch'
import { approvalOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { usePendingApprovalsStore } from './pending'

describe('usePendingApprovalsStore', () => {
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  it('counts the approvals that wait, and follows the approval events', async () => {
    let waiting = [approvalOf()]
    const seen = stubEngine({
      'GET /approvals': () => ({ status: 200, body: { approvals: waiting } }),
    })
    const store = usePendingApprovalsStore()

    stops.push(store.follow())
    await flushPromises()
    expect(seen[0]?.search).toBe('?state=pending')
    expect(store.count).toBe(1)

    const feed = openEventFeed()
    waiting = [approvalOf(), approvalOf({ id: 'apr_2' }), approvalOf({ id: 'apr_3', state: 'approved' })]
    feed.send('approval.requested', { approvalId: 'apr_2' })
    await flushPromises()
    expect(store.count).toBe(2)

    feed.send('run.dispatched')
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(3)
  })

  it('keeps the count it showed when the engine fails', async () => {
    let answer = { status: 200, body: { approvals: [approvalOf()] } as unknown }
    stubEngine({ 'GET /approvals': () => answer })
    const store = usePendingApprovalsStore()
    await store.load()

    answer = { status: 500, body: errorBody('internal', 'Broken.') }
    await store.load()

    expect(store.count).toBe(1)
  })
})
