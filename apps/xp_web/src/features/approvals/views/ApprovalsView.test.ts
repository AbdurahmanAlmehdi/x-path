import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { approvalOf, jobOf, projectOf, releaseOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'

import { armingDelay } from '../stores/approval'

describe('ApprovalsView', () => {
  let app: VueWrapper | undefined
  const decidedBy = {
    tokenId: 'tok_1',
    name: 'Browser',
    kind: 'web' as const,
    personId: 'per_0123456789abcdef',
    personName: 'Sam',
  }
  const waitingJob = jobOf({
    releaseId: 'rel_1',
    steps: [{ ordinal: 0, kind: 'gate', state: 'waitingForApproval', sideEffect: false, attempts: 1 }],
  })

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => {
    app?.unmount()
    vi.useRealTimers()
  })

  function engine(
    routes: Record<string, Answer | (() => Answer)> = {},
    role: 'developer' | 'releaser' = 'releaser',
  ) {
    return stubEngine({
      'GET /me': {
        status: 200,
        body: meOf(role, role === 'developer' ? ['develop'] : ['develop', 'decide_approval', 'release']),
      },
      'GET /projects': { status: 200, body: { projects: [projectOf()] } },
      'GET /approvals': {
        status: 200,
        body: {
          approvals: [
            approvalOf(),
            approvalOf({ id: 'apr_2', state: 'approved', decidedBy, decidedAt: '2026-11-14T09:30:00Z' }),
          ],
        },
      },
      'GET /approvals/apr_1': { status: 200, body: approvalOf() },
      'GET /approvals/apr_2': {
        status: 200,
        body: approvalOf({ id: 'apr_2', state: 'approved', decidedBy, decidedAt: '2026-11-14T09:30:00Z' }),
      },
      'GET /jobs/job_2': { status: 200, body: waitingJob },
      'GET /releases/rel_1': { status: 200, body: releaseOf() },
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  /** Opens the review of apr_1 and waits until Approve is armed. */
  async function review() {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    await button('Approve…').trigger('click')
    expect(app!.find('[role="dialog"]').exists()).toBe(true)
    expect(button('Approve').attributes('disabled')).toBeDefined()
    vi.advanceTimersByTime(armingDelay)
    await flushPromises()
  }

  it('lists what waits, with the first one picked: what it is bound to and what approving does', async () => {
    engine()
    ;({ app } = await openApp('/approvals'))
    await flushPromises()

    expect(app.find('main h1').text()).toBe('Approvals')
    expect(app.find('[data-testid="pending-count"]').text()).toBe('1 pending')
    expect(app.findAll('a.row')).toHaveLength(1)
    expect(app.find('a.row').text()).toContain('Release 1.2.0 (8) to the stores')
    expect(app.find('a.row').text()).toContain('app · production release · 0123456')
    const detail = app.find('[data-testid="approval-detail"]')
    expect(detail.find('h2').text()).toBe('Release 1.2.0 (8) to the stores')
    expect(detail.text()).toContain('prod · com.acme')
    expect(detail.text()).toContain('Approval waits for this')
    expect(detail.find('a[href="/jobs/job_2"]').exists()).toBe(true)
    expect(detail.find('[data-testid="consequence"]').text()).toContain(
      'XPath builds 1.2.0 (8) from 0123456 and releases it to the stores. It goes out as prod · com.acme.',
    )
    expect(app.find('[data-testid="needs-you"]').text()).toBe('1')
  })

  it('approves in the review once it is armed, and shows who approved', async () => {
    let decided = false
    const seen = engine({
      'GET /approvals/apr_1': () => ({
        status: 200,
        body: decided ? approvalOf({ state: 'approved', decidedBy }) : approvalOf(),
      }),
      'POST /approvals/apr_1/approve': () => {
        decided = true
        return { status: 200, body: approvalOf({ state: 'approved', decidedBy, decidedAt: '2026-11-14T09:40:00Z' }) }
      },
    })
    ;({ app } = await openApp('/approvals/apr_1'))
    await flushPromises()

    await review()
    expect(app.find('[role="dialog"]').text()).toContain('Return never approves.')
    await button('Approve').trigger('click')
    await flushPromises()

    expect(seen.some((request) => request.method === 'POST' && request.path === '/approvals/apr_1/approve')).toBe(true)
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(app.find('[data-testid="approval-state-line"]').text()).toMatch(/^by Sam · /)
    expect(app.find('[data-testid="approval-detail"] .actions').exists()).toBe(false)
  })

  it('never approves on Return; ⌘↩ or Ctrl+↩ does, and Escape closes', async () => {
    const seen = engine({
      'POST /approvals/apr_1/approve': { status: 200, body: approvalOf({ state: 'approved', decidedBy }) },
    })
    ;({ app } = await openApp('/approvals/apr_1'))
    await flushPromises()

    await review()
    const dialog = app.find('[role="dialog"]')
    await dialog.trigger('keydown', { key: 'Enter' })
    await flushPromises()
    expect(seen.filter((request) => request.method === 'POST')).toHaveLength(0)
    await dialog.trigger('keydown', { key: 'Escape' })
    expect(app.find('[role="dialog"]').exists()).toBe(false)

    await review()
    await app.find('[role="dialog"]').trigger('keydown', { key: 'Enter', ctrlKey: true })
    await flushPromises()
    expect(seen.filter((request) => request.method === 'POST')).toHaveLength(1)
  })

  it('denies with a reason, and goes back from the denial', async () => {
    const seen = engine({
      'POST /approvals/apr_1/deny': { status: 200, body: approvalOf({ state: 'denied', decidedBy }) },
    })
    ;({ app } = await openApp('/approvals/apr_1'))
    await flushPromises()

    await button('Deny…').trigger('click')
    expect(app.find('[role="dialog"] input').exists()).toBe(true)
    await button('Back').trigger('click')
    expect(app.find('[role="dialog"] input').exists()).toBe(false)
    const dialogDeny = app.find('[role="dialog"]').findAll('button').find((each) => each.text() === 'Deny…')
    await dialogDeny!.trigger('click')
    await app.find('[role="dialog"] input').setValue('Wrong commit.')
    await app.find('[role="dialog"]').trigger('keydown', { key: 'Enter', metaKey: true })
    expect(seen.filter((request) => request.method === 'POST')).toHaveLength(0)
    await button('Deny').trigger('click')
    await flushPromises()

    expect(seen.at(-1)).toMatchObject({
      method: 'POST',
      path: '/approvals/apr_1/deny',
      body: { reason: 'Wrong commit.' },
    })
    expect(app.find('[role="dialog"]').exists()).toBe(false)
  })

  it('shows who won when the approval was decided elsewhere first', async () => {
    engine({
      'POST /approvals/apr_1/approve': {
        status: 409,
        body: {
          error: { code: 'already_decided', message: 'Decided already.' },
          approval: approvalOf({ state: 'denied', decidedBy: { ...decidedBy, personName: 'Ada' } }),
        },
      },
    })
    ;({ app } = await openApp('/approvals/apr_1'))
    await flushPromises()

    await review()
    await button('Approve').trigger('click')
    await flushPromises()

    expect(app.find('[data-testid="already-decided"]').text()).toBe(
      'Already denied by Ada. The first decision counts; nothing to do here.',
    )
    expect(app.find('[data-testid="consequence"]').exists()).toBe(false)
    await button('Close').trigger('click')
    expect(app.find('[role="dialog"]').exists()).toBe(false)
  })

  it('says an approval expired while the review was open, and why the engine refused', async () => {
    let expired = false
    engine({
      'GET /approvals/apr_1': () => ({
        status: 200,
        body: approvalOf(expired ? { state: 'expired' } : {}),
      }),
      'POST /approvals/apr_1/approve': { status: 403, body: errorBody('forbidden', 'Not your role.') },
    })
    ;({ app } = await openApp('/approvals/apr_1'))
    await flushPromises()

    await review()
    await button('Approve').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('Not your role.')

    expired = true
    openEventFeed().send('approval.expired', { approvalId: 'apr_1' })
    await flushPromises()
    expect(app.find('[data-testid="already-decided"]').text()).toContain('This approval expired')
  })

  it('shows a developer the approval with no Approve button', async () => {
    engine({}, 'developer')
    ;({ app } = await openApp('/approvals'))
    await flushPromises()

    expect(app.find('[data-testid="approval-detail"] h2').text()).toBe('Release 1.2.0 (8) to the stores')
    expect(app.findAll('button').map((each) => each.text())).not.toContain('Approve…')
    expect(app.find('[data-testid="cannot-decide"]').exists()).toBe(true)
  })

  it('shows a decided approval under Decided, and an empty filter', async () => {
    engine({ 'GET /approvals': { status: 200, body: { approvals: [approvalOf({ id: 'apr_2', state: 'approved', decidedBy })] } } })
    let router
    ;({ app, router } = await openApp('/approvals'))
    await flushPromises()

    expect(app.find('.empty').text()).toBe('Nothing is waiting')
    await button('Decided').trigger('click')
    await flushPromises()
    expect(app.find('a.row').text()).toContain('Approved')
    expect(app.find('[data-testid="approval-state-line"]').text()).toMatch(/^by Sam · /)

    await router.push('/approvals/apr_2')
    await flushPromises()
    await button('Expired').trigger('click')
    await flushPromises()
    expect(router.currentRoute.value.fullPath).toBe('/approvals')
    expect(app.find('.empty').text()).toBe('Nothing here')
  })

  it('opens an approval by its address under its own filter', async () => {
    engine()
    ;({ app } = await openApp('/approvals/apr_2'))
    await flushPromises()

    expect(app.find('button[aria-pressed="true"]').text()).toBe('Decided')
    expect(app.find('a.row.selected').attributes('href')).toBe('/approvals/apr_2')
  })

  it('says why the approvals could not be read', async () => {
    engine({
      'GET /approvals': { status: 500, body: errorBody('internal', 'Broken.') },
    })
    ;({ app } = await openApp('/approvals'))
    await flushPromises()
    expect(app.find('[role="alert"]').text()).toBe('Broken.')
  })
})
