import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { createMemoryHistory, type Router } from 'vue-router'

import { api } from '@/api/client'
import { useSessionStore } from '@/features/session/stores/session'
import { errorBody, meOf, stubEngine, stubUnreachableEngine } from '@/testing/fetch'

import { createAppRouter, followSessionEnd } from './router'

describe('createAppRouter', () => {
  let router: Router

  beforeEach(() => {
    setActivePinia(createPinia())
    router = createAppRouter(createMemoryHistory())
  })

  function signedOut() {
    stubEngine({ 'GET /me': { status: 401, body: errorBody('unauthorized', 'Sign in.') } })
  }

  function signedIn() {
    stubEngine({ 'GET /me': { status: 200, body: meOf() } })
  }

  it('sends a signed-out deep link to sign-in, with where it was going', async () => {
    signedOut()

    await router.push('/runs/abc')

    expect(router.currentRoute.value.name).toBe('sign-in')
    expect(router.currentRoute.value.query).toEqual({ next: '/runs/abc' })
  })

  it('sends a signed-out visit of home to sign-in without a next', async () => {
    signedOut()

    await router.push('/')

    expect(router.currentRoute.value.fullPath).toBe('/sign-in')
  })

  it('opens any page once signed in', async () => {
    signedIn()

    await router.push('/runs/abc')
    expect(router.currentRoute.value.name).toBe('run')

    await router.push('/approvals/apr_1')
    expect(router.currentRoute.value.name).toBe('approvals')

    await router.push('/runners/abc')
    expect(router.currentRoute.value.name).toBe('not-found')
    expect(router.currentRoute.value.path).toBe('/runners/abc')
  })

  it('sends a signed-in visit of sign-in on to next', async () => {
    signedIn()

    await router.push('/sign-in?next=/runs/abc')

    expect(router.currentRoute.value.fullPath).toBe('/runs/abc')
  })

  it('never follows a next to another site', async () => {
    signedIn()

    await router.push({ name: 'sign-in', query: { next: '//evil.example' } })

    expect(router.currentRoute.value.fullPath).toBe('/')
  })

  it('opens only sign-in when the engine does not answer', async () => {
    stubUnreachableEngine()

    await router.push('/runs')

    expect(router.currentRoute.value.name).toBe('sign-in')
    expect(useSessionStore().status).toBe('unknown')
  })

  describe('followSessionEnd', () => {
    it('goes to sign-in and back to the page when the session ends', async () => {
      signedIn()
      const stop = followSessionEnd(router)
      await router.push('/runs/abc')

      stubEngine({ 'GET /runs': { status: 401 } })
      await api.GET('/runs')
      await router.isReady()
      await new Promise((resolve) => setTimeout(resolve))
      stop()

      expect(useSessionStore().status).toBe('signedOut')
      expect(router.currentRoute.value.name).toBe('sign-in')
      expect(router.currentRoute.value.query).toEqual({ next: '/runs/abc' })
    })

    it('stays on a public page', async () => {
      signedOut()
      await router.push('/sign-in')
      const stop = followSessionEnd(router)

      await api.GET('/me')
      stop()

      expect(router.currentRoute.value.fullPath).toBe('/sign-in')
    })
  })
})
