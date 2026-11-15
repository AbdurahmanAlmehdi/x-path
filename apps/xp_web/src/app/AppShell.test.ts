import { flushPromises, mount, type VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { createMemoryHistory, type Router } from 'vue-router'

import { errorBody, meOf, stubEngine } from '@/testing/fetch'
import { approvalOf } from '@/testing/fixtures'
import { openEventFeed, stubSockets } from '@/testing/sockets'
import { eventually } from '@/testing/wait'

import App from './App.vue'
import { navigation } from './navigation'
import { createAppRouter } from './router'

describe('AppShell', () => {
  let router: Router
  const mounted: VueWrapper[] = []

  beforeEach(() => {
    setActivePinia(createPinia())
    stubSockets()
    router = createAppRouter(createMemoryHistory())
  })
  // The shell follows the engine's events: unmounting closes its feed.
  afterEach(() => mounted.splice(0).forEach((app) => app.unmount()))

  async function open(path: string) {
    await router.push(path)
    const app = mount(App, { global: { plugins: [router] } })
    mounted.push(app)
    await flushPromises()
    return app
  }

  it('shows who is signed in, the navigation and the home page', async () => {
    stubEngine({ 'GET /me': { status: 200, body: meOf('releaser') } })
    const app = await open('/')

    expect(app.find('[data-testid="person-name"]').text()).toBe('Sam')
    expect(app.find('.role').text()).toBe('releaser')
    const links = app.findAll('nav a').map((link) => link.attributes('href'))
    expect(links).toEqual(navigation.flatMap((section) => section.items.map((item) => item.to)))
    expect(app.find('h1').text()).toBe('Welcome, Sam')
  })

  it('says a page is not there yet', async () => {
    stubEngine({ 'GET /me': { status: 200, body: meOf() } })
    const app = await open('/runners/abc')

    expect(app.find('h1').text()).toBe('Nothing here yet')
    expect(app.find('main code').text()).toBe('/runners/abc')
  })

  it('signs out and goes to sign-in', async () => {
    const seen = stubEngine({
      'GET /me': { status: 200, body: meOf() },
      'DELETE /session': { status: 204 },
    })
    const app = await open('/')

    await app.find('header button').trigger('click')
    await flushPromises()

    expect(seen.at(-1)).toMatchObject({ method: 'DELETE', path: '/session' })
    await eventually(() => expect(router.currentRoute.value.fullPath).toBe('/sign-in'))
  })

  it('stays signed in, and says why, when the engine does not end the session', async () => {
    stubEngine({
      'GET /me': { status: 200, body: meOf() },
      'DELETE /session': { status: 500, body: errorBody('internal', 'Broken.') },
    })
    const app = await open('/')

    await app.find('header button').trigger('click')
    await flushPromises()

    expect(app.find('[role="alert"]').text()).toBe('Not signed out: Broken.')
    expect(router.currentRoute.value.fullPath).toBe('/')
    expect(app.find('[data-testid="person-name"]').text()).toBe('Sam')
  })

  it('counts the approvals that wait next to Approvals, and follows them', async () => {
    let waiting = [approvalOf()]
    stubEngine({
      'GET /me': { status: 200, body: meOf() },
      'GET /approvals': () => ({ status: 200, body: { approvals: waiting } }),
    })
    const app = await open('/')

    expect(app.find('a[href="/approvals"] [data-testid="needs-you"]').text()).toBe('1')

    waiting = []
    openEventFeed().send('approval.decided', { approvalId: 'apr_1' })
    await flushPromises()
    expect(app.find('[data-testid="needs-you"]').exists()).toBe(false)
  })
})
