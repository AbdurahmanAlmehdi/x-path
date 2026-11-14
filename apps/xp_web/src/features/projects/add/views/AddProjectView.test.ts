import { flushPromises, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Router } from 'vue-router'

import { followForbidden } from '@/features/session/stores/session'
import { openApp } from '@/testing/app'
import { type Answer, errorBody, meOf, stubEngine } from '@/testing/fetch'
import { projectOf } from '@/testing/fixtures'
import { stubSockets } from '@/testing/sockets'

describe('AddProjectView', () => {
  let app: VueWrapper | undefined
  let router: Router
  const stops: Array<() => void> = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
  })
  afterEach(() => {
    app?.unmount()
    stops.splice(0).forEach((stop) => stop())
  })

  const scanned = projectOf({
    findings: [
      { severity: 'error', code: 'no_flavor', message: 'No flavor is set up.', fix: 'Add a flavor.' },
      { severity: 'info', code: 'note', message: 'A note.', fix: 'Nothing.' },
    ],
  })

  function engine(routes: Record<string, Answer | (() => Answer)> = {}, me = meOf()) {
    return stubEngine({
      'GET /me': { status: 200, body: me },
      'GET /approvals': { status: 200, body: { approvals: [] } },
      'GET /projects': { status: 200, body: { projects: [] } },
      'GET /projects/prj_1': { status: 200, body: scanned },
      'GET /projects/prj_1/workflows': { status: 200, body: { workflows: [] } },
      'GET /projects/prj_1/runs': { status: 200, body: { runs: [], total: 0 } },
      ...routes,
    })
  }

  function button(label: string) {
    const found = app!.findAll('button').find((each) => each.text() === label)
    if (!found) throw new Error(`No button "${label}".`)
    return found
  }

  it('is reached from the projects page by someone who may develop', async () => {
    engine()
    ;({ app, router } = await openApp('/projects'))

    expect(app.find('a.button.primary').text()).toBe('Add project…')
    expect(app.text()).toContain('Add the repository of a Flutter app here')
    expect(router.resolve({ name: 'add-project' }).fullPath).toBe('/projects/add')
  })

  it('adds a repository from a git URL, shows the review of its scan, and opens the project on Done', async () => {
    const seen = engine({ 'POST /projects': { status: 201, body: scanned } })
    ;({ app, router } = await openApp('/projects/add'))

    expect(button('Add and scan').attributes('disabled')).toBeDefined()
    await app.find('form input[type="text"]').setValue('acme/app')
    await app.find('form').trigger('submit')
    await flushPromises()

    expect(seen.find((request) => request.method === 'POST')?.body).toEqual({ remote: 'acme/app' })
    const review = app.find('[data-testid="scan-review"]')
    expect(review.find('h2').text()).toBe('Review the scan of acme/app')
    expect(review.text()).toContain('Error')
    expect(review.text()).toContain('No flavor is set up. Add a flavor.')
    expect(review.text()).toContain('Note')

    await button('Done').trigger('click')
    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/projects/prj_1'))
  })

  it('adds a folder of the engine machine, and offers the SSH URL of an HTTPS origin', async () => {
    const seen = engine({
      'POST /projects': () =>
        (seen.at(-1)?.body as { sshUrl?: string }).sshUrl
          ? { status: 201, body: projectOf() }
          : {
              status: 422,
              body: {
                error: { code: 'ssh_url_required', message: 'XPath reads this host over SSH.' },
                sshUrl: 'git@bitbucket.org:ws/app.git',
              },
            },
    })
    ;({ app } = await openApp('/projects/add'))

    await app.findAll('input[type="radio"]')[1]!.setValue(true)
    expect(app.text()).toContain('The folder has to be on the machine the engine runs on.')
    await app.find('form input[type="text"]').setValue('/src/app')
    await app.find('form').trigger('submit')
    await flushPromises()
    expect(app.find('[role="alert"]').text()).toContain('Add the folder from git@bitbucket.org:ws/app.git instead?')

    await button('Use the SSH URL').trigger('click')
    await flushPromises()
    expect(seen.filter((request) => request.method === 'POST').at(-1)?.body).toEqual({
      path: '/src/app',
      sshUrl: 'git@bitbucket.org:ws/app.git',
    })
    expect(app.find('[data-testid="scan-review"]').text()).toContain('The scan found nothing to fix.')
  })

  it('scans again and removes the project after asking', async () => {
    engine({
      'POST /projects': { status: 201, body: scanned },
      'POST /projects/prj_1/scan': { status: 200, body: projectOf() },
      'DELETE /projects/prj_1': { status: 204 },
    })
    ;({ app } = await openApp('/projects/add'))
    await app.find('form input[type="text"]').setValue('acme/app')
    await app.find('form').trigger('submit')
    await flushPromises()

    await button('Scan again').trigger('click')
    await flushPromises()
    expect(app.text()).toContain('The scan found nothing to fix.')

    await button('Remove project').trigger('click')
    expect(app.find('[role="dialog"]').text()).toContain('Nothing in the folder or on GitHub changes.')
    await button('Keep').trigger('click')
    await button('Remove project').trigger('click')
    await app.find('[role="dialog"] button.danger').trigger('click')
    await flushPromises()

    expect(app.find('[data-testid="scan-review"]').exists()).toBe(false)
    expect(app.text()).toContain('The project was removed.')
  })

  it('says why the engine did not add it', async () => {
    engine({ 'POST /projects': { status: 409, body: errorBody('conflict', 'acme/app is a project already.') } })
    ;({ app } = await openApp('/projects/add'))

    await app.find('form input[type="text"]').setValue('acme/app')
    await app.find('form').trigger('submit')
    await flushPromises()

    expect(app.find('[data-testid="add-error"]').text()).toBe(
      'The engine could not add this: acme/app is a project already.',
    )
  })

  it('reads /me again on a 403 and hides what the person may no longer do', async () => {
    let me = meOf('developer', ['develop'])
    const seen = engine({
      'GET /me': () => ({ status: 200, body: me }),
      'POST /projects': () => {
        me = meOf('viewer', [])
        return { status: 403, body: errorBody('forbidden', 'A viewer cannot add a project.') }
      },
    })
    stops.push(followForbidden())
    ;({ app } = await openApp('/projects/add'))

    await app.find('form input[type="text"]').setValue('acme/app')
    await app.find('form').trigger('submit')
    await flushPromises()

    expect(seen.filter((request) => request.path === '/me')).toHaveLength(2)
    expect(app.find('.role').text()).toBe('viewer')
    expect(app.find('[data-testid="add-project"]').exists()).toBe(false)
    expect(app.find('[data-testid="cannot-add"]').text()).toContain('Your role cannot add projects')
  })
})
