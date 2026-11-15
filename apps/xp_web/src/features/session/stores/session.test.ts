import { flushPromises } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'

import { api } from '@/api/client'

import { errorBody, meOf, stubEngine, stubUnreachableEngine } from '@/testing/fetch'

import { followForbidden, useSessionStore } from './session'

describe('useSessionStore', () => {
  beforeEach(() => setActivePinia(createPinia()))

  it('starts unknown, with no person and no permission', () => {
    const session = useSessionStore()

    expect(session.status).toBe('unknown')
    expect(session.person).toBeNull()
    expect(session.can('develop')).toBe(false)
  })

  describe('load', () => {
    it('knows who is signed in, and what they may do', async () => {
      stubEngine({ 'GET /me': { status: 200, body: meOf('developer', ['develop']) } })
      const session = useSessionStore()

      await session.load()

      expect(session.status).toBe('signedIn')
      expect(session.person?.name).toBe('Sam')
      expect(session.can('develop')).toBe(true)
      expect(session.can('decide_approval')).toBe(false)
    })

    it('is signed out on 401', async () => {
      stubEngine({ 'GET /me': { status: 401, body: errorBody('unauthorized', 'Sign in.') } })
      const session = useSessionStore()

      await session.load()

      expect(session.status).toBe('signedOut')
      expect(session.me).toBeNull()
    })

    it('asks the engine once', async () => {
      const seen = stubEngine({ 'GET /me': { status: 200, body: meOf() } })
      const session = useSessionStore()

      await session.load()
      await session.load()

      expect(seen).toHaveLength(1)
    })

    it('throws on any other answer and stays unknown', async () => {
      stubEngine({ 'GET /me': { status: 500, body: errorBody('internal', 'Broken.') } })
      const session = useSessionStore()

      await expect(session.load()).rejects.toThrow('Broken.')
      expect(session.status).toBe('unknown')
    })
  })

  describe('signIn', () => {
    it('exchanges the code for a session', async () => {
      const seen = stubEngine({ 'POST /session': { status: 200, body: meOf() } })
      const session = useSessionStore()

      const failure = await session.signIn('ABCD-EFGH-JKMN-PQRS')

      expect(failure).toBeNull()
      expect(seen[0]?.body).toEqual({ code: 'ABCD-EFGH-JKMN-PQRS' })
      expect(session.status).toBe('signedIn')
      expect(session.person?.role).toBe('admin')
    })

    it('says a wrong, used or expired code alike', async () => {
      stubEngine({ 'POST /session': { status: 401, body: errorBody('unauthorized', 'No.') } })
      const session = useSessionStore()

      expect(await session.signIn('nope')).toBe(
        'That code is wrong, used or expired. Ask for a new one.',
      )
      expect(session.status).toBe('unknown')
    })

    it('says when there were too many wrong codes', async () => {
      stubEngine({ 'POST /session': { status: 429, body: errorBody('rate_limited', 'Slow.') } })

      expect(await useSessionStore().signIn('nope')).toBe(
        'Too many wrong codes. Wait a few minutes, then try again.',
      )
    })

    it('passes on the reason the engine refuses, with its hint', async () => {
      stubEngine({
        'POST /session': {
          status: 403,
          body: errorBody('forbidden', 'Sign-in needs HTTPS here.', 'Set a public URL.'),
        },
      })

      expect(await useSessionStore().signIn('ABCD')).toBe(
        'Sign-in needs HTTPS here. Set a public URL.',
      )
    })
  })

  describe('signOut', () => {
    it('ends the session on the engine, then here', async () => {
      const seen = stubEngine({
        'POST /session': { status: 200, body: meOf() },
        'DELETE /session': { status: 204 },
      })
      const session = useSessionStore()
      await session.signIn('ABCD')

      await session.signOut()

      expect(seen.map((request) => `${request.method} ${request.path}`)).toContain(
        'DELETE /session',
      )
      expect(session.status).toBe('signedOut')
      expect(session.person).toBeNull()
    })

    it('forgets a session the engine had already ended', async () => {
      stubEngine({
        'POST /session': { status: 200, body: meOf() },
        'DELETE /session': { status: 401, body: errorBody('unauthorized', 'Sign in.') },
      })
      const session = useSessionStore()
      await session.signIn('ABCD')

      expect(await session.signOut()).toBeNull()
      expect(session.status).toBe('signedOut')
    })

    it('keeps the session when the engine refuses or does not answer', async () => {
      stubEngine({
        'POST /session': { status: 200, body: meOf() },
        'DELETE /session': { status: 403, body: errorBody('csrf', 'Missing the CSRF header.') },
      })
      const session = useSessionStore()
      await session.signIn('ABCD')

      expect(await session.signOut()).toBe('Missing the CSRF header.')
      expect(session.status).toBe('signedIn')

      stubUnreachableEngine()
      expect(await session.signOut()).toBe('The engine did not answer. Check that it is running.')
      expect(session.person?.name).toBe('Sam')
    })
  })

  it('forgets the session when told it ended', async () => {
    stubEngine({ 'GET /me': { status: 200, body: meOf() } })
    const session = useSessionStore()
    await session.load()

    session.signedOut()

    expect(session.status).toBe('signedOut')
    expect(session.can('develop')).toBe(false)
  })

  it('throws when the engine cannot be reached', async () => {
    stubUnreachableEngine()

    await expect(useSessionStore().signIn('ABCD')).rejects.toThrow()
  })

  describe('refresh', () => {
    it('reads what the session may do again after a refusal', async () => {
      let me = meOf('developer', ['develop'])
      stubEngine({
        'GET /me': () => ({ status: 200, body: me }),
        'POST /people': { status: 403, body: errorBody('forbidden', 'A viewer cannot add a person.') },
      })
      const session = useSessionStore()
      await session.load()
      const stop = followForbidden()

      me = meOf('viewer', [])
      await api.POST('/people', { body: { name: 'Dana', role: 'viewer' } })
      await flushPromises()
      stop()

      expect(session.person?.role).toBe('viewer')
      expect(session.can('develop')).toBe(false)
    })

    it('asks nothing while signed out, and keeps what it knew when the engine fails', async () => {
      const seen = stubEngine({ 'GET /me': { status: 200, body: meOf() } })
      const session = useSessionStore()
      await session.refresh()
      expect(seen).toHaveLength(0)

      await session.load()
      stubUnreachableEngine()
      await session.refresh()
      stubEngine({ 'GET /me': { status: 500, body: errorBody('internal', 'Broken.') } })
      await session.refresh()

      expect(session.status).toBe('signedIn')
      expect(session.can('administer')).toBe(true)
    })
  })
})
