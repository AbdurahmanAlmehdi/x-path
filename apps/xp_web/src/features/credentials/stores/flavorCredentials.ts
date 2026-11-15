import { defineStore } from 'pinia'
import { ref } from 'vue'

import {
  api,
  dataOf,
  doneOf,
  errorMessage,
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

/** A distribution certificate of the team, which the owner could revoke to make room. */
export interface TeamCertificate {
  id: string
  serialNumber: string
  name?: string
  expirationDate?: string
}

/** The team is at Apple's limit of distribution certificates (`409`, `certificate_limit`). */
export interface CertificateLimit {
  limit: number
  certificates: TeamCertificate[]
}

/** The limit the engine's refusal [refusal] names, or `null` when it is another refusal. */
function limitOf(refusal: unknown): CertificateLimit | null {
  const details = (refusal as { error?: { details?: Partial<Record<string, unknown>> } } | undefined)?.error?.details
  if (details?.reason !== 'certificate_limit') return null
  return {
    limit: Number(details.limit),
    certificates: Array.isArray(details.certificates) ? (details.certificates as TeamCertificate[]) : [],
  }
}

/**
 * The credential each flavor of one project uses, by kind, with both checks
 * (D-07), assigning a named credential to a flavor or taking it away, and
 * creating an Apple Distribution certificate for a flavor on the engine.
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
  /** Whether the engine is creating a distribution certificate. */
  const creating = ref(false)
  /** What the engine said when it refused the last certificate. */
  const certificateError = ref<string | null>(null)
  /** The team's certificates, when the last one was refused at Apple's limit. */
  const certificateLimit = ref<CertificateLimit | null>(null)

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

  /** Forgets how the last certificate went, for a new attempt. */
  function resetCertificate() {
    certificateError.value = null
    certificateLimit.value = null
  }

  /**
   * The engine creates an Apple Distribution certificate with the App Store
   * Connect key of [target], and assigns the identity, called [name], to it
   * (ADR 0014). At Apple's limit, [certificateLimit] lists the team's
   * certificates.
   */
  async function createCertificate(target: FlavorTarget, name: string): Promise<boolean> {
    const project = projectId.value
    if (!project) return false
    creating.value = true
    resetCertificate()
    try {
      const { data, error: refusal, response } = await api.POST(
        '/projects/{id}/flavors/{flavor}/distribution-certificate',
        {
          params: { path: { id: project, flavor: target.flavor }, query: { app: target.app } },
          body: { name: name.trim() },
        },
      )
      if (data) {
        await load(project)
        return true
      }
      certificateLimit.value = limitOf(refusal)
      certificateError.value = errorMessage(refusal, response.status)
      return false
    } catch (failure) {
      certificateError.value = failureMessage(failure)
      return false
    } finally {
      creating.value = false
    }
  }

  return {
    projectId,
    credentials,
    loaded,
    error,
    assigning,
    assignError,
    kept,
    creating,
    certificateError,
    certificateLimit,
    open,
    follow,
    of,
    assign,
    unassign,
    resetCertificate,
    createCertificate,
  }
})
