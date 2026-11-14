import { defineStore } from 'pinia'
import { ref } from 'vue'

import {
  api,
  dataOf,
  doneOf,
  failureMessage,
  type Credential,
  type CredentialKind,
} from '@/api/client'
import { followEvents } from '@/api/sockets'

import type { FlavorTarget } from '../labels'

/** What an assignment asks for besides the flavor it is made from. */
export interface AssignOptions {
  /** Every flavor of the app uses it too. */
  allFlavors?: boolean
  /** With [allFlavors], the flavors that have their own give it up. */
  replace?: boolean
}

/**
 * The credential each flavor of one project uses, by kind, with both checks
 * (D-07), and assigning a named credential to a flavor or taking it away.
 */
export const useFlavorCredentialsStore = defineStore('flavorCredentials', () => {
  const projectId = ref<string | null>(null)
  const credentials = ref<Credential[]>([])
  const loaded = ref(false)
  const error = ref<string | null>(null)
  /** Whether an assignment is on its way to the engine. */
  const assigning = ref(false)
  /** What the engine said when it refused the last assignment. */
  const assignError = ref<string | null>(null)
  /** The flavors that kept their own credential at the last assignment. */
  const kept = ref<string[]>([])

  async function load(project: string) {
    try {
      const read = await dataOf(
        api.GET('/projects/{id}/credentials', { params: { path: { id: project } } }),
      )
      if (projectId.value !== project) return
      credentials.value = read.credentials
      error.value = null
    } catch (failure) {
      if (projectId.value === project) error.value = failureMessage(failure)
    } finally {
      if (projectId.value === project) loaded.value = true
    }
  }

  /** Shows the credentials of the flavors of [project]. */
  async function open(project: string): Promise<void> {
    if (projectId.value !== project) {
      projectId.value = project
      credentials.value = []
      loaded.value = false
      error.value = null
    }
    await load(project)
  }

  /** Loads again on credential events and a resync. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      const concerns = item.kind === 'resync' || item.event.type.startsWith('credential.')
      if (concerns && projectId.value) void load(projectId.value)
    })
  }

  /** The credentials [target] uses. */
  function of(target: FlavorTarget): Credential[] {
    return credentials.value.filter(
      (credential) => credential.app === target.app && credential.flavor === target.flavor,
    )
  }

  async function change(send: () => Promise<void>): Promise<boolean> {
    const project = projectId.value
    if (!project) return false
    assigning.value = true
    assignError.value = null
    kept.value = []
    try {
      await send()
      await load(project)
      return true
    } catch (failure) {
      assignError.value = failureMessage(failure)
      return false
    } finally {
      assigning.value = false
    }
  }

  function path(target: FlavorTarget, kind: CredentialKind) {
    return {
      path: { id: projectId.value ?? '', flavor: target.flavor, kind },
      query: { app: target.app },
    }
  }

  /** Has [target] use the credential [credentialId] of [kind]. */
  function assign(
    target: FlavorTarget,
    kind: CredentialKind,
    credentialId: string,
    options: AssignOptions = {},
  ): Promise<boolean> {
    return change(async () => {
      const answer = await dataOf(
        api.PUT('/projects/{id}/flavors/{flavor}/credentials/{kind}', {
          params: path(target, kind),
          body: { credentialId, allFlavors: options.allFlavors ?? false, replace: options.replace ?? false },
        }),
      )
      kept.value = answer.kept.map((credential) => credential.flavor)
    })
  }

  /** Has [target] use no credential of [kind]. */
  function unassign(target: FlavorTarget, kind: CredentialKind): Promise<boolean> {
    return change(() =>
      doneOf(api.DELETE('/projects/{id}/flavors/{flavor}/credentials/{kind}', { params: path(target, kind) })),
    )
  }

  return {
    projectId,
    credentials,
    loaded,
    error,
    assigning,
    assignError,
    kept,
    open,
    follow,
    of,
    assign,
    unassign,
  }
})
