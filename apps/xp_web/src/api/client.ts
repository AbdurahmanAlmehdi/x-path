import createClient, { type Middleware } from 'openapi-fetch'

import type { components, paths } from './schema'

/** Where the engine serves its API (ADR 0018). */
export const apiBase = '/api/v1'

export type Me = components['schemas']['Me']
export type Permission = components['schemas']['Permission']
export type ApiError = components['schemas']['ErrorResponse']['error']

type Listener = () => void

const signedOutListeners = new Set<Listener>()

/**
 * Calls [listener] whenever the engine answers `401` to a request of the
 * signed-in app: the session ended (signed out elsewhere, revoked, expired).
 * Returns the function that stops it.
 */
export function onSignedOut(listener: Listener): () => void {
  signedOutListeners.add(listener)
  return () => signedOutListeners.delete(listener)
}

/**
 * Every request carries `X-XPath-CSRF: 1`, which a page on another site
 * cannot add without a preflight the engine never answers (D14). A `401`
 * means the session is over, except for the sign-in itself, whose `401`
 * is a wrong code.
 */
export const sessionMiddleware: Middleware = {
  onRequest({ request }) {
    request.headers.set('X-XPath-CSRF', '1')
    return request
  },
  onResponse({ request, response, schemaPath }) {
    const signingIn = schemaPath === '/session' && request.method === 'POST'
    if (response.status === 401 && !signingIn) {
      signedOutListeners.forEach((listener) => listener())
    }
    return response
  },
}

/**
 * The typed client of the engine's API, on the page's own origin. It looks
 * `fetch` up on every call, so tests replace it at the network layer.
 */
export const api = createClient<paths>({
  baseUrl: new URL(apiBase, window.location.origin).href,
  credentials: 'same-origin',
  fetch: (request) => globalThis.fetch(request),
})
api.use(sessionMiddleware)

/**
 * The error message of a failed call: the engine's own, with its hint, or
 * a generic one when the answer is not the error envelope.
 */
export function errorMessage(error: unknown, status: number): string {
  const body = (error as { error?: Partial<ApiError> } | undefined)?.error
  if (typeof body?.message === 'string') {
    return body.hint ? `${body.message} ${body.hint}` : body.message
  }
  return `The engine answered ${status}.`
}
