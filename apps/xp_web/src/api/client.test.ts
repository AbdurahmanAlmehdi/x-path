import { afterEach, describe, expect, it, vi } from 'vitest'

import { errorBody, meOf, stubEngine, stubUnreachableEngine } from '@/testing/fetch'

import { api, apiBase, errorMessage, onSignedOut } from './client'

describe('api', () => {
  const stops: Array<() => void> = []
  afterEach(() => stops.splice(0).forEach((stop) => stop()))

  function listen() {
    const listener = vi.fn()
    stops.push(onSignedOut(listener))
    return listener
  }

  it('calls the API under /api/v1 on the page origin', async () => {
    stubEngine({ 'GET /me': { status: 200, body: meOf() } })

    const { data } = await api.GET('/me')

    expect(apiBase).toBe('/api/v1')
    expect(data?.person.name).toBe('Sam')
  })

  it('sends the CSRF header with every request', async () => {
    const seen = stubEngine({
      'GET /me': { status: 200, body: meOf() },
      'DELETE /session': { status: 204 },
    })

    await api.GET('/me')
    await api.DELETE('/session')

    expect(seen.map((request) => request.headers.get('x-xpath-csrf'))).toEqual(['1', '1'])
  })

  it('tells the listeners when the engine answers 401', async () => {
    stubEngine({ 'GET /me': { status: 401, body: errorBody('unauthorized', 'Sign in.') } })
    const listener = listen()

    await api.GET('/me')

    expect(listener).toHaveBeenCalledOnce()
  })

  it('does not take a wrong sign-in code for the end of a session', async () => {
    stubEngine({ 'POST /session': { status: 401, body: errorBody('unauthorized', 'No.') } })
    const listener = listen()

    await api.POST('/session', { body: { code: 'AAAA' } })

    expect(listener).not.toHaveBeenCalled()
  })

  it('stays quiet on other answers, and after a listener stops', async () => {
    stubEngine({
      'GET /me': { status: 200, body: meOf() },
      'DELETE /session': { status: 401 },
    })
    const listener = vi.fn()
    const stop = onSignedOut(listener)

    await api.GET('/me')
    stop()
    await api.DELETE('/session')

    expect(listener).not.toHaveBeenCalled()
  })

  it('throws when the engine cannot be reached', async () => {
    stubUnreachableEngine()

    await expect(api.GET('/me')).rejects.toThrow('Failed to fetch')
  })
})

describe('errorMessage', () => {
  it('is the message of the error envelope', () => {
    expect(errorMessage(errorBody('forbidden', 'Not allowed.'), 403)).toBe('Not allowed.')
  })

  it('adds the hint', () => {
    expect(errorMessage(errorBody('forbidden', 'Not over HTTP.', 'Set a public URL.'), 403)).toBe(
      'Not over HTTP. Set a public URL.',
    )
  })

  it('names the status when the answer is not the envelope', () => {
    expect(errorMessage(undefined, 502)).toBe('The engine answered 502.')
    expect(errorMessage({ error: { code: 'x' } }, 500)).toBe('The engine answered 500.')
  })
})
