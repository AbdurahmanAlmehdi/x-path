import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory, type Router } from 'vue-router'

import App from '@/app/App.vue'
import { navigation } from '@/app/navigation'
import { createAppRouter } from '@/app/router'
import { meOf, stubEngine } from '@/testing/fetch'

describe('AppShell', () => {
  let router: Router

  beforeEach(() => {
    setActivePinia(createPinia())
    router = createAppRouter(createMemoryHistory())
  })

  async function open(path: string) {
    await router.push(path)
    const app = mount(App, { global: { plugins: [router] } })
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
    const app = await open('/approvals/abc')

    expect(app.find('h1').text()).toBe('Nothing here yet')
    expect(app.find('main code').text()).toBe('/approvals/abc')
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
    await vi.waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/sign-in'))
  })
})
