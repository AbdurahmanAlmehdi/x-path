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
  /** What the engine said when it refused the last change, such as the last admin's `409`. */
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

  /** Runs [change] for the person [id]; `true` when the engine took it. */
  async function changed(id: string, change: () => Promise<unknown>): Promise<boolean> {
    changing.value = id
    actionError.value = null
    try {
      await change()
      await load()
      return true
    } catch (failure) {
      actionError.value = failureMessage(failure)
      return false
    } finally {
      changing.value = null
    }
  }

  /** Adds [name] with [role]. Throws the engine's refusal. */
  async function add(name: string, role: PersonRole): Promise<Person> {
    const person = await dataOf(api.POST('/people', { body: { name: name.trim(), role } }))
    await load()
    return person
  }

  /** Gives the person [id] the role [role]. */
  function setRole(id: string, role: PersonRole): Promise<boolean> {
    return changed(id, () =>
      dataOf(api.PATCH('/people/{id}', { params: { path: { id } }, body: { role } })),
    )
  }

  /** Removes the person [id] and revokes their tokens. */
  function remove(id: string): Promise<boolean> {
    return changed(id, () => doneOf(api.DELETE('/people/{id}', { params: { path: { id } } })))
  }

  /** A one-time sign-in code for the person [id], for the caller to show once. Throws the engine's refusal. */
  function signInCode(id: string): Promise<SignInCode> {
    return dataOf(api.POST('/people/{id}/sign-in-codes', { params: { path: { id } } }))
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
    add,
    setRole,
    remove,
    signInCode,
  }
})
