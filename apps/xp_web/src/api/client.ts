import createClient, { type Middleware } from 'openapi-fetch'

import type { components, paths } from './schema'

/** Where the engine serves its API (ADR 0018). */
export const apiBase = '/api/v1'

type Schemas = components['schemas']

export type Me = Schemas['Me']
export type Permission = Schemas['Permission']
export type ApiError = Schemas['ErrorResponse']['error']
export type Project = Schemas['Project']
export type AppProfile = Schemas['AppProfile']
export type Run = Schemas['Run']
export type RunState = Schemas['RunState']
export type RunJob = Schemas['RunJob']
export type Job = Schemas['Job']
export type JobState = Schemas['JobState']
export type JobStep = Schemas['JobStep']
export type StepState = Schemas['StepState']
export type WorkflowSummary = Schemas['WorkflowSummary']
export type Workflow = Schemas['Workflow']
export type WorkflowInput = Schemas['WorkflowInput']
export type WorkflowSchema = Schemas['WorkflowSchema']
export type DispatchRequest = Schemas['DispatchRequest']
export type DispatchPlan = Schemas['DispatchPlan']
export type VersionBump = Schemas['VersionBump']
export type Release = Schemas['Release']
export type SequencedEvent = Schemas['SequencedEvent']
export type LogFrame = Schemas['LogFrame']
export type LogLineFrame = Schemas['LogLineFrame']

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
 * Tells the [onSignedOut] listeners that the engine ended the session: a
 * `401`, or a socket it closed with 4401 (D12).
 */
export function sessionEnded() {
  signedOutListeners.forEach((listener) => listener())
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
    if (response.status === 401 && !signingIn) sessionEnded()
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

/** A call the engine refused or failed, with what it said. */
export class ApiFailure extends Error {
  constructor(
    message: string,
    readonly status: number,
    /** The engine's error code, or its `details.reason` when it gives one. */
    readonly reason: string | undefined,
  ) {
    super(message)
    this.name = 'ApiFailure'
  }
}

/**
 * The data of a call, or an [ApiFailure] with the engine's message when it
 * answered something else. A call that never reached the engine throws as
 * `fetch` does.
 */
export async function dataOf<T>(
  call: Promise<{ data?: T; error?: unknown; response: Response }>,
): Promise<T> {
  const { data, error, response } = await call
  if (data !== undefined) return data
  const body = (error as { error?: Partial<ApiError> } | undefined)?.error
  const reason = (body?.details as { reason?: unknown } | undefined)?.reason
  throw new ApiFailure(
    errorMessage(error, response.status),
    response.status,
    typeof reason === 'string' ? reason : body?.code,
  )
}

/** What to tell people about a failed call. */
export function failureMessage(failure: unknown): string {
  return failure instanceof ApiFailure
    ? failure.message
    : 'The engine did not answer. Check that it is running.'
}
