import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  api,
  ApiFailure,
  doneOf,
  errorMessage,
  failureMessage,
  onForbidden,
  type Me,
  type Permission,
} from '@/api/client'

/** What the app knows about the browser's session. */
export type SessionStatus = 'unknown' | 'signedIn' | 'signedOut'

/** The outcome of a sign-in: `null` when it worked, else why not. */
export type SignInFailure = string | null

/**
 * The signed-in person and what they may do (D16). The app hides what
 * `permissions` leaves out; the engine decides.
 */
export const useSessionStore = defineStore('session', () => {
  const me = ref<Me | null>(null)
  const status = ref<SessionStatus>('unknown')

  const person = computed(() => me.value?.person ?? null)

  function can(permission: Permission): boolean {
    return me.value?.permissions.includes(permission) ?? false
  }

  function signedIn(who: Me) {
    me.value = who
    status.value = 'signedIn'
  }

  /** Forgets the session: the engine ended it, or the browser signed out. */
  function signedOut() {
    me.value = null
    status.value = 'signedOut'
  }

  /**
   * Asks the engine who the browser is signed in as, once. A `401` means
   * signed out; any other failure is thrown, so the app does not mistake an
   * engine that is down for a signed-out browser.
   */
  async function load(): Promise<void> {
    if (status.value !== 'unknown') return
    const { data, error, response } = await api.GET('/me')
    if (data) return signedIn(data)
    if (response.status === 401) return signedOut()
    throw new Error(errorMessage(error, response.status))
  }

  /**
   * Asks the engine again what the session may do, after it refused
   * something: a role changes on the next request (D12), and the app hides
   * what the person may no longer do. A `401` ends the session through the
   * client; any other failure keeps what the app knew.
   */
  async function refresh(): Promise<void> {
    if (status.value !== 'signedIn') return
    try {
      const { data } = await api.GET('/me')
      if (data) signedIn(data)
    } catch {
      // The engine did not answer: the next refusal asks again.
    }
  }

  /** Exchanges a one-time sign-in code for the session cookie (D10). */
  async function signIn(code: string): Promise<SignInFailure> {
    const { data, error, response } = await api.POST('/session', {
      body: { code },
    })
    if (data) {
      signedIn(data)
      return null
    }
    if (response.status === 401) {
      return 'That code is wrong, used or expired. Ask for a new one.'
    }
    if (response.status === 429) {
      return 'Too many wrong codes. Wait a few minutes, then try again.'
    }
    return errorMessage(error, response.status)
  }

  /**
   * Ends the session on the engine, then here: `null` when it ended, else
   * why not. A refused or unanswered sign-out keeps the session, whose
   * cookie still works on the engine; a `401` means it had ended already.
   */
  async function signOut(): Promise<string | null> {
    try {
      await doneOf(api.DELETE('/session'))
    } catch (failure) {
      if (!(failure instanceof ApiFailure && failure.status === 401)) return failureMessage(failure)
    }
    signedOut()
    return null
  }

  return { me, status, person, can, load, refresh, signIn, signOut, signedOut }
})

/**
 * Reads `/me` again whenever the engine answers `403`, so a person whose
 * role changed sees at once what they may still do. Returns the function
 * that stops following.
 */
export function followForbidden(): () => void {
  return onForbidden(() => void useSessionStore().refresh())
}
