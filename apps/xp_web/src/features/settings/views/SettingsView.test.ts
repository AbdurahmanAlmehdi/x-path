import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { stubSockets } from '@/testing/sockets'

describe('SettingsView', () => {
  let app: VueWrapper | undefined

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => app?.unmount())

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, admin = true) {
    return stubEngine({
      'GET /me': { status: 200, body: admin ? meOf() : meOf('developer', ['develop']) },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /settings/public-url': { status: 200, body: {} },
      'GET /settings/runner-url': { status: 200, body: { url: 'http://mac-mini.local:7480' } },
      'GET /github-token': { status: 200, body: { stored: true, status: 'verified', login: 'octo' } },
      ...routes,
    })
  }

  function section(name: string) {
    return app!.find(`[data-testid="${name}"]`)
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  it('shows each setting as it stands', async () => {
    engine()
    ;({ app } = await openApp('/settings'))

    expect(section('public-url').text()).toContain('No public URL is set: browsers sign in on the engine machine only.')
    expect(section('runner-url').text()).toContain('Runners reach the engine at http://mac-mini.local:7480.')
    expect(section('github-status').text()).toBe('Connected to GitHub as octo.')
  })

  it('sets the public URL and clears it', async () => {
    const seen = engine({
      'PUT /settings/public-url': () => {
        const body = seen.at(-1)?.body as { url: string | null }
        return { status: 200, body: body.url ? { url: body.url } : {} }
      },
    })
    ;({ app } = await openApp('/settings'))

    await section('public-url').find('input').setValue('https://xpath.example.com')
    await section('public-url').trigger('submit')
    await flushPromises()
    expect(section('public-url').text()).toContain('Browsers sign in through https://xpath.example.com.')

    await section('public-url').findAll('button').find((each) => each.text() === 'Clear')!.trigger('click')
    await flushPromises()
    expect(section('public-url').text()).toContain('No public URL is set')
  })

  it('shows the refusal of a public URL, and the warning of a runner URL', async () => {
    engine({
      'PUT /settings/public-url': { status: 400, body: errorBody('invalid_request', 'The public URL must be https.') },
      'PUT /settings/runner-url': {
        status: 200,
        body: { url: 'http://192.168.1.2:7480', warning: 'Plain http leaves this machine.' },
      },
    })
    ;({ app } = await openApp('/settings'))

    await section('public-url').find('input').setValue('http://xpath.example.com')
    await section('public-url').trigger('submit')
    await flushPromises()
    expect(section('public-url').find('[role="alert"]').text()).toBe('The public URL must be https.')

    await section('runner-url').find('input').setValue('http://192.168.1.2:7480')
    await section('runner-url').trigger('submit')
    await flushPromises()
    expect(section('runner-url').text()).toContain('Plain http leaves this machine.')
    await section('runner-url').findAll('button').find((each) => each.text() === 'Clear')!.trigger('click')
  })

  it('keeps the GitHub token write-only: a password field, never shown back, emptied once saved', async () => {
    const seen = engine({
      'GET /github-token': { status: 200, body: { stored: false } },
      'PUT /github-token': { status: 200, body: { stored: true, status: 'verified' } },
    })
    ;({ app } = await openApp('/settings'))
    expect(section('github-status').text()).toContain('The engine has no GitHub token')

    const field = section('github').find('input')
    expect(field.attributes('type')).toBe('password')
    expect(field.attributes('autocomplete')).toBe('off')
    await field.setValue('ghp_fake_secret')
    await section('github').trigger('submit')
    await flushPromises()

    expect(seen.find((request) => request.method === 'PUT')?.body).toEqual({ token: 'ghp_fake_secret' })
    expect((section('github').find('input').element as HTMLInputElement).value).toBe('')
    expect(app.html()).not.toContain('ghp_fake_secret')
    expect(section('github-status').text()).toBe('Connected to GitHub.')
  })

  it('says why GitHub refused, imports from gh and removes the token after asking', async () => {
    engine({
      'GET /github-token': {
        status: 200,
        body: { stored: true, status: 'rejected', message: 'Bad credentials.', fix: 'Make a new token.' },
      },
      'PUT /github-token': { status: 422, body: errorBody('credential_rejected', 'GitHub refused it.') },
      'POST /github-token/import': {
        status: 200,
        body: { stored: true, status: 'unreachable', message: 'GitHub is down.' },
      },
      'DELETE /github-token': { status: 204 },
    })
    ;({ app } = await openApp('/settings'))
    expect(section('github-status').text()).toBe("GitHub refused the engine's token: Bad credentials. Make a new token.")

    await section('github').find('input').setValue('ghp_bad')
    await section('github').trigger('submit')
    await flushPromises()
    expect(section('github').find('[role="alert"]').text()).toBe('Not saved: GitHub refused it.')

    await button('Import from GitHub CLI').trigger('click')
    await flushPromises()
    expect(section('github-status').text()).toBe("GitHub could not check the engine's token: GitHub is down.")

    await button('Remove token').trigger('click')
    expect(app.find('[role="dialog"]').text()).toContain('The token stays valid on GitHub')
    await button('Keep').trigger('click')
    await button('Remove token').trigger('click')
    await app.find('[role="dialog"] button.danger').trigger('click')
    await flushPromises()
    expect(app.find('[role="dialog"]').exists()).toBe(false)
    expect(section('github-status').text()).toContain('The engine has no GitHub token')
  })

  it('keeps the removal open with its refusal', async () => {
    engine({ 'DELETE /github-token': { status: 403, body: errorBody('forbidden', 'Admins only.') } })
    ;({ app } = await openApp('/settings'))

    await button('Remove token').trigger('click')
    await app.find('[role="dialog"] button.danger').trigger('click')
    await flushPromises()

    expect(app.find('[role="dialog"] [role="alert"]').text()).toBe('Admins only.')
  })

  it('shows a developer the settings without a field to change them', async () => {
    engine({}, false)
    ;({ app } = await openApp('/settings'))

    expect(app.findAll('main input')).toHaveLength(0)
    expect(app.findAll('main button')).toHaveLength(0)
    expect(section('github-status').text()).toBe('Connected to GitHub as octo.')
  })
})
