import { afterEach, describe, expect, it, vi } from 'vitest'

import { errorBody, meOf, stubEngine, stubUnreachableEngine } from '@/testing/fetch'

import {
  api,
  apiBase,
  ApiFailure,
  dataOf,
  doneOf,
  errorMessage,
  failureMessage,
  onForbidden,
  onSignedOut,
  sessionEnded,
} from './client'

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

  it('tells the forbidden listeners when the engine answers 403, until they stop', async () => {
    stubEngine({
      'POST /people': { status: 403, body: errorBody('forbidden', 'A viewer cannot add a person.') },
      'POST /session': { status: 403, body: errorBody('forbidden', 'Not from here.') },
      'GET /me': { status: 200, body: meOf() },
    })
    const listener = vi.fn()
    const stop = onForbidden(listener)

    await api.POST('/people', { body: { name: 'Dana', role: 'developer' } })
    await api.POST('/session', { body: { code: 'AAAA' } })
    await api.GET('/me')
    expect(listener).toHaveBeenCalledOnce()

    stop()
    await api.POST('/people', { body: { name: 'Dana', role: 'developer' } })
    expect(listener).toHaveBeenCalledOnce()
  })

  it('tells the listeners when a socket ends the session', () => {
    const listener = listen()

    sessionEnded()

    expect(listener).toHaveBeenCalledOnce()
  })
})

describe('dataOf', () => {
  it('is the data of a call that worked', async () => {
    stubEngine({ 'GET /me': { status: 200, body: meOf() } })

    expect((await dataOf(api.GET('/me'))).person.name).toBe('Sam')
  })

  it('throws the message, status and code of the engine', async () => {
    stubEngine({ 'GET /projects': { status: 403, body: errorBody('forbidden', 'Not you.') } })

    const failure = await dataOf(api.GET('/projects')).catch((error: unknown) => error)

    expect(failure).toBeInstanceOf(ApiFailure)
    expect(failure).toMatchObject({ message: 'Not you.', status: 403, reason: 'forbidden' })
  })

  it('takes the reason from the details when the engine gives one', async () => {
    stubEngine({
      'GET /projects': {
        status: 422,
        body: { error: { code: 'workflow_invalid', message: 'No main.', details: { reason: 'ref_unknown' } } },
      },
    })

    await expect(dataOf(api.GET('/projects'))).rejects.toMatchObject({ reason: 'ref_unknown' })
  })

  it('has no reason when the answer is not the envelope', async () => {
    stubEngine({ 'GET /projects': { status: 502 } })

    await expect(dataOf(api.GET('/projects'))).rejects.toMatchObject({
      message: 'The engine answered 502.',
      reason: undefined,
    })
  })
})

describe('doneOf', () => {
  it('resolves when a call without a body worked', async () => {
    stubEngine({ 'DELETE /session': { status: 204 } })

    await expect(doneOf(api.DELETE('/session'))).resolves.toBeUndefined()
  })

  it('throws the message and status of the engine otherwise', async () => {
    stubEngine({ 'DELETE /session': { status: 403, body: errorBody('forbidden', 'Not a browser.') } })

    const failure = await doneOf(api.DELETE('/session')).catch((error: unknown) => error)

    expect(failure).toBeInstanceOf(ApiFailure)
    expect(failure).toMatchObject({ message: 'Not a browser.', status: 403, reason: 'forbidden' })
  })
})

describe('failureMessage', () => {
  it('is the message of the engine', () => {
    expect(failureMessage(new ApiFailure('Not you.', 403, 'forbidden'))).toBe('Not you.')
  })

  it('says the engine did not answer otherwise', () => {
    expect(failureMessage(new TypeError('Failed to fetch'))).toBe(
      'The engine did not answer. Check that it is running.',
    )
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
