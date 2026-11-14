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
export type ReleaseState = Schemas['ReleaseState']
export type ReleaseStore = Schemas['ReleaseStore']
export type StoreState = Schemas['StoreState']
export type StoreStatus = Schemas['StoreStatus']
export type StatusSource = Schemas['StatusSource']
export type ReleaseEvent = Schemas['ReleaseEvent']
export type ReleaseNotes = Schemas['ReleaseNotes']
export type ReleaseTexts = Schemas['ReleaseTexts']
export type RolloutRequest = Schemas['RolloutRequest']
export type PatchAction = Schemas['PatchAction']
export type Credential = Schemas['Credential']
export type Approval = Schemas['Approval']
export type ApprovalState = Schemas['ApprovalState']
export type GateAction = Schemas['GateAction']
export type TestRunResponse = Schemas['TestRunResponse']
export type TestRun = Schemas['TestRun']
export type TestCase = Schemas['TestCase']
export type TestRef = Schemas['TestRef']
export type TestBaseline = Schemas['TestBaseline']
export type SequencedEvent = Schemas['SequencedEvent']
export type LogFrame = Schemas['LogFrame']
export type LogLineFrame = Schemas['LogLineFrame']
export type Person = Schemas['Person']
export type PersonRole = Schemas['PersonRole']
export type SignInCode = Schemas['SignInCode']
export type TokenInfo = Schemas['TokenInfo']
export type CreatedToken = Schemas['CreatedToken']
export type Runner = Schemas['Runner']
export type PairingToken = Schemas['PairingToken']
export type RunnerUrl = Schemas['RunnerUrl']
export type PublicUrl = Schemas['PublicUrl']
export type GitHubTokenStatus = Schemas['GitHubTokenStatus']
export type StorageReport = Schemas['StorageReport']
export type StorageCategory = Schemas['StorageCategory']
export type RetentionSettings = Schemas['RetentionSettings']
export type FreeSpaceResult = Schemas['FreeSpaceResult']
export type NamedCredential = Schemas['NamedCredential']
export type CredentialKind = Schemas['CredentialKind']
export type CredentialStatus = Schemas['CredentialStatus']
export type CredentialUsage = Schemas['CredentialUsage']
export type CreateCredentialRequest = Schemas['CreateCredentialRequest']
export type ReplaceCredentialRequest = Schemas['ReplaceCredentialRequest']
export type AssignCredentialResponse = Schemas['AssignCredentialResponse']
export type Finding = Schemas['Finding']

type Listener = () => void

const signedOutListeners = new Set<Listener>()
const forbiddenListeners = new Set<Listener>()

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
 * Calls [listener] whenever the engine answers `403` to a request: the
 * person's role may have changed since `/me` was read (D12, D16). Returns
 * the function that stops it.
 */
export function onForbidden(listener: Listener): () => void {
  forbiddenListeners.add(listener)
  return () => forbiddenListeners.delete(listener)
}

/**
 * Every request carries `X-XPath-CSRF: 1`, which a page on another site
 * cannot add without a preflight the engine never answers (D14). A `401`
 * means the session is over, except for the sign-in itself, whose `401`
 * is a wrong code. A `403` tells the [onForbidden] listeners, so the app
 * reads `/me` again and hides what the person may no longer do.
 */
export const sessionMiddleware: Middleware = {
  onRequest({ request }) {
    request.headers.set('X-XPath-CSRF', '1')
    return request
  },
  onResponse({ request, response, schemaPath }) {
    const signingIn = schemaPath === '/session' && request.method === 'POST'
    if (response.status === 401 && !signingIn) sessionEnded()
    if (response.status === 403 && !signingIn) forbiddenListeners.forEach((listener) => listener())
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
  throw failureOf(error, response)
}

/**
 * Waits for a call that answers without a body, such as a `204`; throws an
 * [ApiFailure] with the engine's message when it answered something else.
 */
export async function doneOf(call: Promise<{ error?: unknown; response: Response }>): Promise<void> {
  const { error, response } = await call
  if (!response.ok) throw failureOf(error, response)
}

function failureOf(error: unknown, response: Response): ApiFailure {
  const body = (error as { error?: Partial<ApiError> } | undefined)?.error
  const reason = (body?.details as { reason?: unknown } | undefined)?.reason
  return new ApiFailure(
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
