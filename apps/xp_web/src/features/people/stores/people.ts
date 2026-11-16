import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import { api, dataOf, doneOf, type Person, type PersonRole, type SignInCode } from '@/api/client'
import { useCommand, useLoad } from '@/api/requests'

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
  /**
   * The person a change is on its way for ([busy]), and what the engine
   * said when it refused the last action ([error]), such as the last
   * admin's `409`. Every action shares the one refusal; [dismiss] forgets
   * it, as a dialog opens or closes.
   */
  const change = useCommand<string | null>(null)

  /** The people who may sign in, oldest first. */
  const active = computed(() => people.value.filter((person) => !person.removedAt))
  /** The people removed, kept for the names on approvals and runs. */
  const removed = computed(() => people.value.filter((person) => person.removedAt))

  /** Asks the engine for the people. */
  const { loaded, error, load } = useLoad(async () => {
    people.value = (await dataOf(api.GET('/people'))).people
  })

  /** The name of the person [id], or the id when the engine did not say. */
  function nameOf(id: string | undefined): string {
    return people.value.find((person) => person.id === id)?.name ?? id ?? ''
  }

  /** Adds [name] with [role]: the new person, or `null`. */
  function add(name: string, role: PersonRole): Promise<Person | null> {
    return change.run(null, async () => {
      const person = await dataOf(api.POST('/people', { body: { name: name.trim(), role } }))
      await load()
      return person
    })
  }

  /** Gives the person [id] the role [role]; `true` when the engine took it. */
  async function setRole(id: string, role: PersonRole): Promise<boolean> {
    const changed = await change.run(id, async () => {
      await dataOf(api.PATCH('/people/{id}', { params: { path: { id } }, body: { role } }))
      await load()
      return true
    })
    return changed ?? false
  }

  /** Removes the person [id] and revokes their tokens; `true` when the engine took it. */
  async function remove(id: string): Promise<boolean> {
    const removed = await change.run(id, async () => {
      await doneOf(api.DELETE('/people/{id}', { params: { path: { id } } }))
      await load()
      return true
    })
    return removed ?? false
  }

  /** A one-time sign-in code for the person [id], for the caller to show once; `null` when refused. */
  function signInCode(id: string): Promise<SignInCode | null> {
    return change.run(id, () => dataOf(api.POST('/people/{id}/sign-in-codes', { params: { path: { id } } })))
  }

  return {
    people,
    loaded,
    error,
    changing: change.busy,
    actionError: change.error,
    active,
    removed,
    load,
    nameOf,
    dismiss: change.dismiss,
    add,
    setRole,
    remove,
    signInCode,
  }
})
