import { flushPromises, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { createMemoryHistory, type Router } from 'vue-router'

import { createAppRouter } from '@/app/router'
import { errorBody, meOf, stubEngine, stubUnreachableEngine } from '@/testing/fetch'
import { eventually } from '@/testing/wait'

import SignInView from './SignInView.vue'

describe('SignInView', () => {
  let router: Router

  beforeEach(() => {
    window.history.replaceState(null, '', '/')
    setActivePinia(createPinia())
    router = createAppRouter(createMemoryHistory())
  })

  async function open(path = '/sign-in') {
    await router.push(path)
    const view = mount(SignInView, { global: { plugins: [router] } })
    await flushPromises()
    return view
  }

  it('signs in with the code typed, then goes to next', async () => {
    const seen = stubEngine({
      'GET /me': { status: 401 },
      'POST /session': { status: 200, body: meOf() },
    })
    const view = await open('/sign-in?next=/runs/abc')

    await view.find('input').setValue('  ABCD-EFGH-JKMN-PQRS ')
    await view.find('form').trigger('submit')
    await flushPromises()

    expect(seen.at(-1)?.body).toEqual({ code: 'ABCD-EFGH-JKMN-PQRS' })
    await eventually(() => expect(router.currentRoute.value.fullPath).toBe('/runs/abc'))
  })

  it('takes the code from the fragment, drops it from the address and signs in', async () => {
    const seen = stubEngine({
      'GET /me': { status: 401 },
      'POST /session': { status: 200, body: meOf() },
    })
    window.history.replaceState({ kept: true }, '', '/sign-in?next=%2Fruns#code=ABCD-EFGH')

    await open('/sign-in?next=/runs')

    expect(window.location.hash).toBe('')
    expect(window.location.pathname + window.location.search).toBe('/sign-in?next=%2Fruns')
    expect(window.history.state).toEqual({ kept: true })
    expect(seen.at(-1)?.body).toEqual({ code: 'ABCD-EFGH' })
    await eventually(() => expect(router.currentRoute.value.fullPath).toBe('/runs'))
  })

  it('drops a refused code from the fragment too, and says why', async () => {
    const seen = stubEngine({
      'GET /me': { status: 401 },
      'POST /session': { status: 401, body: errorBody('unauthorized', 'No.') },
    })
    window.history.replaceState(null, '', '/sign-in#code=USED-CODE')

    const view = await open()

    expect(seen.at(-1)?.body).toEqual({ code: 'USED-CODE' })
    expect(window.location.hash).toBe('')
    expect(view.find('[role="alert"]').text()).toBe(
      'That code is wrong, used or expired. Ask for a new one.',
    )
    expect(router.currentRoute.value.name).toBe('sign-in')
  })

  it('goes home after sign-in without a next, or with one to another site', async () => {
    stubEngine({
      'GET /me': { status: 401 },
      'POST /session': { status: 200, body: meOf() },
    })
    window.history.replaceState(null, '', '/sign-in#code=ABCD')

    await open('/sign-in?next=//evil.example')

    await eventually(() => expect(router.currentRoute.value.fullPath).toBe('/'))
  })

  it('shows why a code is refused, and stays', async () => {
    stubEngine({
      'GET /me': { status: 401 },
      'POST /session': { status: 401, body: errorBody('unauthorized', 'No.') },
    })
    const view = await open()

    await view.find('input').setValue('WRONG')
    await view.find('form').trigger('submit')
    await flushPromises()

    expect(view.find('[role="alert"]').text()).toBe(
      'That code is wrong, used or expired. Ask for a new one.',
    )
    expect(view.find('input').attributes('aria-invalid')).toBe('true')
    expect(router.currentRoute.value.name).toBe('sign-in')
  })

  it('says when the engine does not answer', async () => {
    stubUnreachableEngine()
    const view = await open()

    await view.find('input').setValue('ABCD')
    await view.find('form').trigger('submit')
    await flushPromises()

    expect(view.find('[role="alert"]').text()).toBe(
      'The engine did not answer. Check that it is running.',
    )
    expect(view.find('button').attributes('disabled')).toBeUndefined()
  })

  it('sends nothing without a code', async () => {
    const seen = stubEngine({ 'GET /me': { status: 401 } })
    const view = await open()

    await view.find('input').setValue('   ')
    await view.find('form').trigger('submit')
    await flushPromises()

    expect(seen.map((request) => request.method)).not.toContain('POST')
  })

  it('sends one request while one is on its way', async () => {
    const seen = stubEngine({
      'GET /me': { status: 401 },
      'POST /session': { status: 401 },
    })
    const view = await open()

    await view.find('input').setValue('ABCD')
    await view.find('form').trigger('submit')
    await view.find('form').trigger('submit')
    await flushPromises()

    expect(seen.filter((request) => request.method === 'POST')).toHaveLength(1)
  })
})
