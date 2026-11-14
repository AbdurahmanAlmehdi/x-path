import { vi } from 'vitest'

/** A request the stubbed `fetch` received. */
export interface SeenRequest {
  method: string
  path: string
  /** The query, such as `?limit=1`; empty without one. */
  search: string
  headers: Headers
  body: unknown
}

/** An answer of the stubbed engine: a status and a JSON body. */
export interface Answer {
  status: number
  body?: unknown
}

/**
 * Replaces `fetch` with an engine that answers each `METHOD /path` (the
 * path under `/api/v1`) from [routes], and `404` otherwise. Returns what
 * it received.
 */
export function stubEngine(routes: Record<string, Answer | (() => Answer)>): SeenRequest[] {
  const seen: SeenRequest[] = []
  vi.stubGlobal('fetch', async (request: Request) => {
    const url = new URL(request.url)
    const path = url.pathname.replace(/^\/api\/v1/, '')
    const text = await request.text()
    seen.push({
      method: request.method,
      path,
      search: url.search,
      headers: request.headers,
      body: text === '' ? undefined : JSON.parse(text),
    })
    const route = routes[`${request.method} ${path}`]
    const answer = typeof route === 'function' ? route() : (route ?? { status: 404 })
    return new Response(answer.body === undefined ? null : JSON.stringify(answer.body), {
      status: answer.status,
      headers: { 'content-type': 'application/json' },
    })
  })
  return seen
}

/** Replaces `fetch` with one that cannot reach the engine. */
export function stubUnreachableEngine() {
  vi.stubGlobal('fetch', async () => {
    throw new TypeError('Failed to fetch')
  })
}

/** The answer of `GET /me` or `POST /session` for a person with a role. */
export function meOf(
  role: 'viewer' | 'developer' | 'releaser' | 'admin' = 'admin',
  permissions: Array<'develop' | 'decide_approval' | 'release' | 'administer'> = [
    'develop',
    'decide_approval',
    'release',
    'administer',
  ],
) {
  return {
    person: { id: 'per_0123456789abcdef', name: 'Sam', role, createdAt: '2026-11-14T09:00:00Z' },
    token: {
      id: 'tok_0123456789abcdef',
      name: 'Browser',
      kind: 'web',
      createdAt: '2026-11-14T09:00:00Z',
      personId: 'per_0123456789abcdef',
    },
    permissions,
  }
}

/** The engine's error envelope. */
export function errorBody(code: string, message: string, hint?: string) {
  return { error: { code, message, ...(hint ? { hint } : {}) } }
}
