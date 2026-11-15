import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { errorBody, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { approvalOf, jobOf, releaseOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { armingDelay, useApprovalStore } from './approval'

describe('useApprovalStore', () => {
  const stops: Array<() => void> = []
  const decidedBy = { tokenId: 'tok_9', name: 'Mac mini', kind: 'app' as const, personName: 'Ada' }

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => {
    stops.splice(0).forEach((stop) => stop())
    vi.useRealTimers()
  })

  function engine(routes = {}) {
    return stubEngine({
      'GET /approvals/apr_1': { status: 200, body: approvalOf() },
      'GET /jobs/job_2': { status: 200, body: jobOf({ releaseId: 'rel_1' }) },
      'GET /releases/rel_1': { status: 200, body: releaseOf() },
      ...routes,
    })
  }

  /** The store with apr_1 open and its review armed. */
  async function armed(routes = {}) {
    vi.useFakeTimers()
    const seen = engine(routes)
    const store = useApprovalStore()
    await store.open('apr_1')
    store.review()
    vi.advanceTimersByTime(armingDelay)
    return { store, seen }
  }

  it('shows the approval with the job that waits for it and the release it builds', async () => {
    engine()
    const store = useApprovalStore()

    await store.open('apr_1')

    expect(store.approval?.id).toBe('apr_1')
    expect(store.pending).toBe(true)
    expect(store.job?.id).toBe('job_2')
    expect(store.release?.id).toBe('rel_1')
  })

  it('goes without the release of a job that builds none, and without a job it cannot read', async () => {
    engine({ 'GET /jobs/job_2': { status: 200, body: jobOf() } })
    const store = useApprovalStore()
    await store.open('apr_1')
    expect(store.job?.id).toBe('job_2')
    expect(store.release).toBeNull()

    setActivePinia(createPinia())
    engine({ 'GET /approvals/apr_1': { status: 200, body: approvalOf({ jobId: undefined }) } })
    const bare = useApprovalStore()
    await bare.open('apr_1')
    expect(bare.job).toBeNull()

    setActivePinia(createPinia())
    engine({ 'GET /jobs/job_2': { status: 500, body: errorBody('internal', 'Broken.') } })
    const broken = useApprovalStore()
    await broken.open('apr_1')
    expect(broken.approval?.id).toBe('apr_1')
    expect(broken.error).toBeNull()
  })

  it('knows an approval that is not there, says why one could not be read, and drops stale answers', async () => {
    engine({
      'GET /approvals/apr_2': { status: 404, body: errorBody('not_found', 'No.') },
      'GET /approvals/apr_3': { status: 500, body: errorBody('internal', 'Broken.') },
    })
    const store = useApprovalStore()

    await store.open('apr_2')
    expect(store.missing).toBe(true)
    await store.open('apr_3')
    expect(store.missing).toBe(false)
    expect(store.error).toBe('Broken.')

    const first = store.open('apr_1')
    const second = store.open('apr_2')
    await Promise.all([first, second])
    expect(store.approval).toBeNull()
    const third = store.open('apr_3')
    await store.open('apr_1')
    await third
    expect(store.error).toBeNull()
  })

  it('drops the subject of an approval it no longer shows', async () => {
    let release: () => void = () => {}
    const blocked = new Promise<void>((resolve) => {
      release = resolve
    })
    engine({ 'GET /approvals/apr_2': { status: 200, body: approvalOf({ id: 'apr_2', jobId: 'job_9' }) } })
    const fetch = globalThis.fetch
    vi.stubGlobal('fetch', async (request: Request) => {
      if (request.url.endsWith('/jobs/job_2') || request.url.endsWith('/releases/rel_1')) await blocked
      return fetch(request)
    })
    const store = useApprovalStore()

    const first = store.open('apr_1')
    await flushPromises()
    await store.open('apr_2')
    release()
    await first

    expect(store.job).toBeNull()
  })

  it('follows its own events', async () => {
    const seen = engine()
    const store = useApprovalStore()
    await store.open('apr_1')
    stops.push(store.follow())
    const feed = openEventFeed()
    seen.length = 0

    feed.send('approval.decided', { approvalId: 'apr_2' })
    feed.send('job.state_changed', { approvalId: 'apr_1' })
    await flushPromises()
    expect(seen).toHaveLength(0)

    feed.send('approval.decided', { approvalId: 'apr_1' })
    await flushPromises()
    feed.resync()
    await flushPromises()
    expect(seen).toHaveLength(2)
  })

  it('arms Approve a moment after the review opens; Deny works at once', async () => {
    vi.useFakeTimers()
    engine()
    const store = useApprovalStore()
    await store.open('apr_1')

    store.review()
    expect(store.reviewing).toBe(true)
    expect(store.canApprove).toBe(false)
    expect(store.canDeny).toBe(true)
    expect(await store.decide('approve')).toBe(false)

    vi.advanceTimersByTime(armingDelay)
    expect(store.canApprove).toBe(true)

    store.close()
    expect(store.reviewing).toBe(false)
    expect(store.canApprove).toBe(false)
  })

  it('approves, and the answer is the decision that counts', async () => {
    const { store, seen } = await armed({
      'POST /approvals/apr_1/approve': {
        status: 200,
        body: approvalOf({ state: 'approved', decidedBy }),
      },
    })

    const answer = store.decide('approve')
    expect(store.deciding).toBe('approve')
    expect(store.canDeny).toBe(false)
    expect(await answer).toBe(true)

    expect(seen.at(-1)).toMatchObject({ method: 'POST', path: '/approvals/apr_1/approve', body: {} })
    expect(store.approval?.state).toBe('approved')
    expect(store.deciding).toBeNull()
  })

  it('denies with a reason, and without a blank one', async () => {
    const { store, seen } = await armed({
      'POST /approvals/apr_1/deny': { status: 200, body: approvalOf({ state: 'pending' }) },
    })

    expect(await store.decide('deny', '  Not today. ')).toBe(true)
    expect(seen.at(-1)).toMatchObject({ path: '/approvals/apr_1/deny', body: { reason: 'Not today.' } })
    expect(await store.decide('deny', '   ')).toBe(true)
    expect(seen.at(-1)?.body).toEqual({})
  })

  it('shows who won when another device decided first', async () => {
    const { store } = await armed({
      'POST /approvals/apr_1/approve': {
        status: 409,
        body: {
          error: { code: 'already_decided', message: 'Decided already.' },
          approval: approvalOf({ state: 'denied', decidedBy }),
        },
      },
    })

    expect(await store.decide('approve')).toBe(false)

    expect(store.approval?.state).toBe('denied')
    expect(store.approval?.decidedBy?.personName).toBe('Ada')
    expect(store.pending).toBe(false)
    expect(store.canDeny).toBe(false)
    expect(store.decisionError).toBeNull()
  })

  it('says why the engine refused, or could not be reached', async () => {
    const { store } = await armed({
      'POST /approvals/apr_1/approve': { status: 403, body: errorBody('forbidden', 'Not your role.') },
    })

    expect(await store.decide('approve')).toBe(false)
    expect(store.decisionError).toBe('Not your role.')
    expect(store.pending).toBe(true)

    stubUnreachableEngine()
    expect(await store.decide('approve')).toBe(false)
    expect(store.decisionError).toBe('The engine did not answer. Check that it is running.')
  })

  it('decides nothing before it shows an approval', async () => {
    expect(await useApprovalStore().decide('deny')).toBe(false)
  })
})
