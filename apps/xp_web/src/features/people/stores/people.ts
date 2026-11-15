import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  api,
  dataOf,
  doneOf,
  failureMessage,
  type Person,
  type PersonRole,
  type SignInCode,
} from '@/api/client'
import { coalesced } from '@/app/coalesce'

/** The roles, each allowed everything the ones before it are (ADR 0017). */
export const roles: PersonRole[] = ['viewer', 'developer', 'releaser', 'admin']

/**
 * Everyone who uses the engine, and what an admin does with them: add,
 * change the role, remove, and issue a sign-in code (D8, D13). A code is
 * handed to the caller and never kept here: the dialog that shows it holds
 * it, and forgets it when it closes.
 */
export const usePeopleStore = defineStore('people', () => {
  const people = ref<Person[]>([])
  const loaded = ref(false)
  const error = ref<string | null>(null)
  /** The person a change is on its way for. */
  const changing = ref<string | null>(null)
  /** What the engine said when it refused the last action, such as the last admin's `409`. */
  const actionError = ref<string | null>(null)

  /** The people who may sign in, oldest first. */
  const active = computed(() => people.value.filter((person) => !person.removedAt))
  /** The people removed, kept for the names on approvals and runs. */
  const removed = computed(() => people.value.filter((person) => person.removedAt))

  /** Asks the engine for the people. */
  const load = coalesced(async () => {
    try {
      people.value = (await dataOf(api.GET('/people'))).people
      error.value = null
    } catch (failure) {
      error.value = failureMessage(failure)
    } finally {
      loaded.value = true
    }
  })

  /** The name of the person [id], or the id when the engine did not say. */
  function nameOf(id: string | undefined): string {
    return people.value.find((person) => person.id === id)?.name ?? id ?? ''
  }

  /**
   * Runs [action], for the person [id] when it is about one; what the
   * engine answered, or `null` with [actionError] saying why not.
   */
  async function act<T>(id: string | null, action: () => Promise<T>): Promise<T | null> {
    changing.value = id
    actionError.value = null
    try {
      return await action()
    } catch (failure) {
      actionError.value = failureMessage(failure)
      return null
    } finally {
      changing.value = null
    }
  }

  /** Forgets the last refusal, as a dialog opens or closes. */
  function dismiss() {
    actionError.value = null
  }

  /** Adds [name] with [role]: the new person, or `null`. */
  function add(name: string, role: PersonRole): Promise<Person | null> {
    return act(null, async () => {
      const person = await dataOf(api.POST('/people', { body: { name: name.trim(), role } }))
      await load()
      return person
    })
  }

  /** Gives the person [id] the role [role]; `true` when the engine took it. */
  async function setRole(id: string, role: PersonRole): Promise<boolean> {
    const changed = await act(id, async () => {
      await dataOf(api.PATCH('/people/{id}', { params: { path: { id } }, body: { role } }))
      await load()
      return true
    })
    return changed ?? false
  }

  /** Removes the person [id] and revokes their tokens; `true` when the engine took it. */
  async function remove(id: string): Promise<boolean> {
    const removed = await act(id, async () => {
      await doneOf(api.DELETE('/people/{id}', { params: { path: { id } } }))
      await load()
      return true
    })
    return removed ?? false
  }

  /** A one-time sign-in code for the person [id], for the caller to show once; `null` when refused. */
  function signInCode(id: string): Promise<SignInCode | null> {
    return act(id, () => dataOf(api.POST('/people/{id}/sign-in-codes', { params: { path: { id } } })))
  }

  return {
    people,
    loaded,
    error,
    changing,
    actionError,
    active,
    removed,
    load,
    nameOf,
    dismiss,
    add,
    setRole,
    remove,
    signInCode,
  }
})
