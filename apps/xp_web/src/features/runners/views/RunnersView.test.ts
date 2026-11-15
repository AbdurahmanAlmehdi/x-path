import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import type { Router } from 'vue-router'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { runnerOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

describe('RunnersView', () => {
  let app: VueWrapper | undefined
  let router: Router

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
    localStorage.clear()
    sessionStorage.clear()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, admin = true) {
    return stubEngine({
      'GET /me': { status: 200, body: admin ? meOf() : meOf('developer', ['develop']) },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /runners': {
        status: 200,
        body: {
          runners: [
            runnerOf({
              jobIds: ['job_1'],
              missing: [{ capability: 'ios-sign', reason: 'No Xcode', fix: 'Install Xcode' }],
            }),
            runnerOf({ id: 'rnr_2', name: 'fresh', capabilities: [], lastHeartbeat: undefined }),
            runnerOf({ id: 'rnr_3', name: 'old', status: 'revoked', revokedAt: '2026-11-12T09:00:00Z' }),
          ],
        },
      },
      'GET /settings/runner-url': { status: 200, body: {} },
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  it('lists the runners with their status, capabilities and slots, and the revoked apart', async () => {
    engine()
    ;({ app } = await openApp('/runners'))

    expect(app.find('main h1').text()).toBe('Runners')
    expect(app.find('main header').text()).toContain('2 runners · 1 busy')
    const rows = app.findAll('[data-testid="runners"] tbody tr')
    expect(rows).toHaveLength(2)
    expect(rows[0]!.text()).toContain('macos · arm64 · xp 1.4.0 · 10 cores')
    expect(rows[0]!.text()).toContain('Online · busy 1/2')
    expect(rows[0]!.text()).toContain('android · flutter')
    expect(rows[0]!.text()).toContain('No ios-sign: No Xcode. Install Xcode.')
    expect(rows[1]!.text()).toContain('Not probed yet')
    expect(rows[1]!.text()).toContain('Never')
    expect(app.text()).toContain('Revoked')
    expect(app.text()).toContain('old')
  })

  it('says when there is no runner, and shows no admin action to a developer', async () => {
    engine({ 'GET /runners': { status: 200, body: { runners: [] } } }, false)
    ;({ app } = await openApp('/runners'))

    expect(app.text()).toContain('No runners yet')
    expect(app.findAll('button').map((each) => each.text())).not.toContain('Pair runner…')
  })

  it('shows a pairing token once, keeps it out of the address and storage, and forgets it on Done', async () => {
    const seen = engine({
      'POST /runners/pairing-tokens': {
        status: 201,
        body: { token: 'xpp_fake_token', name: 'linux-box', expiresAt: new Date(Date.now() + 600_000).toISOString() },
      },
    })
    ;({ app, router } = await openApp('/runners'))

    await button('Pair runner…').trigger('click')
    const dialog = () => app!.find('[role="dialog"]')
    expect(dialog().text()).toContain('It works once, for 15 minutes, and is shown only now.')
    await dialog().find('input').setValue('linux-box')
    await button('Create pairing token').trigger('click')
    await flushPromises()

    expect(seen.find((request) => request.method === 'POST')?.body).toEqual({ name: 'linux-box' })
    expect(dialog().text()).toContain('Pairing token for linux-box')
    expect(dialog().text()).toContain('xp runner pair --engine http://localhost:3000 --token xpp_fake_token')
    expect(dialog().find('[data-testid="only-here"]').exists()).toBe(true)
    expect(dialog().find('[data-testid="expires"]').text()).toMatch(/^Works once; expires in \dm/)
    expect(router.currentRoute.value.fullPath).toBe('/runners')
    expect(JSON.stringify({ ...localStorage })).not.toContain('xpp_fake_token')
    expect(JSON.stringify({ ...sessionStorage })).not.toContain('xpp_fake_token')

    await button('Done').trigger('click')
    await flushPromises()
    expect(dialog().exists()).toBe(false)
    expect(app.html()).not.toContain('xpp_fake_token')
  })

  it('says why a pairing token was refused, and offers a new one once it expired', async () => {
    let calls = 0
    engine({
      'POST /runners/pairing-tokens': () =>
        ++calls === 1
          ? { status: 409, body: errorBody('conflict', 'The name mac-mini is taken.') }
          : { status: 201, body: { token: `xpp_${calls}`, name: 'other', expiresAt: '2026-01-01T00:00:00Z' } },
      'GET /settings/runner-url': { status: 200, body: { url: 'http://mac-mini.local:7480' } },
    })
    ;({ app } = await openApp('/runners'))

    await button('Pair runner…').trigger('click')
    await app.find('[role="dialog"] input').setValue('mac-mini')
    await app.find('[role="dialog"] form').trigger('submit')
    await flushPromises()
    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('The name mac-mini is taken.')

    await app.find('[role="dialog"] input').setValue('other')
    await button('Create pairing token').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').text()).toContain('--engine http://mac-mini.local:7480 --token xpp_2')
    expect(app.find('[data-testid="only-here"]').exists()).toBe(false)
    expect(app.find('[role="dialog"]').text()).toContain('Expired before it was used.')

    await button('New token').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').text()).toContain('--token xpp_3')

    await button('Done').trigger('click')
    expect(app.find('[role="dialog"]').exists()).toBe(false)
  })

  it('revokes a runner after saying what happens to its jobs', async () => {
    let revoked = false
    engine({
      'GET /runners': () => ({
        status: 200,
        body: { runners: [runnerOf({ status: revoked ? 'revoked' : 'online', jobIds: revoked ? [] : ['job_1', 'job_2'] })] },
      }),
      'POST /runners/rnr_1/revoke': () => {
        revoked = true
        return { status: 200, body: runnerOf({ status: 'revoked' }) }
      },
    })
    ;({ app } = await openApp('/runners'))

    await button('Revoke…').trigger('click')
    const dialog = app.find('[role="dialog"]')
    expect(dialog.attributes('aria-label')).toBe('Revoke mac-mini?')
    expect(dialog.text()).toContain('The 2 jobs it holds are queued again')
    expect(dialog.text()).toContain('The name mac-mini stays taken')
    await button('Keep').trigger('click')
    expect(app.find('[role="dialog"]').exists()).toBe(false)

    await button('Revoke…').trigger('click')
    await button('Revoke').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(app.text()).toContain('No runners yet')
  })

  it('keeps the confirmation open with the refusal, and names a single job', async () => {
    engine({
      'GET /runners': { status: 200, body: { runners: [runnerOf({ jobIds: ['job_1'] })] } },
      'POST /runners/rnr_1/revoke': { status: 403, body: errorBody('forbidden', 'A developer cannot revoke a runner.') },
    })
    ;({ app } = await openApp('/runners'))

    await button('Revoke…').trigger('click')
    expect(app.find('[role="dialog"]').text()).toContain('The job it holds is queued again')
    await button('Revoke').trigger('click')
    await flushPromises()

    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('A developer cannot revoke a runner.')
  })
})
