import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { errorBody, stubEngine } from '@/testing/fetch'
import { approvalOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { filterOf, useApprovalsStore } from './approvals'

describe('useApprovalsStore', () => {
  const stops: Array<() => void> = []
  const approvals = [
    approvalOf({ id: 'apr_3' }),
    approvalOf({ id: 'apr_2', state: 'approved' }),
    approvalOf({ id: 'apr_1', state: 'expired' }),
    approvalOf({ id: 'apr_0', state: 'denied' }),
  ]

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  it('files each state under its filter', () => {
    expect(['pending', 'approved', 'denied', 'expired'].map((state) => filterOf(state as never))).toEqual([
      'pending',
      'decided',
      'decided',
      'expired',
    ])
  })

  it('lists the approvals under a filter, and shows the first of them', async () => {
    stubEngine({ 'GET /approvals': { status: 200, body: { approvals } } })
    const store = useApprovalsStore()

    await store.load()

    expect(store.loaded).toBe(true)
    expect(store.pendingCount).toBe(1)
    expect(store.visible.map((approval) => approval.id)).toEqual(['apr_3'])
    expect(store.selected?.id).toBe('apr_3')

    store.show('decided')
    expect(store.visible.map((approval) => approval.id)).toEqual(['apr_2', 'apr_0'])
    store.select('apr_0')
    expect(store.selected?.id).toBe('apr_0')
    store.select(null)
    expect(store.selected?.id).toBe('apr_2')
  })

  it('shows a picked approval under its own filter, once it arrives', async () => {
    stubEngine({ 'GET /approvals': { status: 200, body: { approvals } } })
    const store = useApprovalsStore()

    store.select('apr_1')
    await store.load()

    expect(store.filter).toBe('expired')
    expect(store.selected?.id).toBe('apr_1')

    // Picking a filter afterwards is not undone by the next load.
    store.show('pending')
    await store.load()
    expect(store.filter).toBe('pending')
  })

  it('follows the picked approval to its new filter once it is decided', async () => {
    let listed = approvals
    stubEngine({ 'GET /approvals': () => ({ status: 200, body: { approvals: listed } }) })
    const store = useApprovalsStore()
    store.select('apr_3')
    await store.load()
    expect(store.filter).toBe('pending')

    listed = [approvalOf({ id: 'apr_3', state: 'approved' }), ...approvals.slice(1)]
    await store.load()

    expect(store.filter).toBe('decided')
    expect(store.selected?.id).toBe('apr_3')
  })

  it('says why the approvals could not be read', async () => {
    stubEngine({ 'GET /approvals': { status: 500, body: errorBody('internal', 'Broken.') } })
    const store = useApprovalsStore()

    await store.load()

    expect(store.error).toBe('Broken.')
    expect(store.selected).toBeNull()
  })

  it('loads again on approval events and on a resync', async () => {
    const seen = stubEngine({ 'GET /approvals': { status: 200, body: { approvals } } })
    const store = useApprovalsStore()
    stops.push(store.follow())
    const feed = openEventFeed()

    feed.send('job.state_changed', { projectId: 'prj_1' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('approval.requested', { approvalId: 'apr_4' })
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(2)
  })
})
