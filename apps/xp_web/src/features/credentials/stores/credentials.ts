import { defineStore } from 'pinia'
import { ref } from 'vue'

import {
  api,
  dataOf,
  doneOf,
  type CreateCredentialRequest,
  type NamedCredential,
  type ReplaceCredentialRequest,
} from '@/api/client'
import { useCommand, useLoad } from '@/api/requests'
import { followEvents } from '@/api/sockets'

import { statusOf } from '../labels'

/** What the credentials page is sending to the engine. */
export type CredentialCommand = 'saving' | 'verifying' | 'renaming' | 'deleting'

/**
 * The engine's named credentials, never their secrets, kept up to date by
 * the credential events, and what an admin does with them: add one, replace
 * its secret, rename, check and delete it.
 *
 * A request that carries a secret goes straight to the engine and is never
 * kept here; the engine checks it before it stores it and never sends it
 * back.
 */
export const useCredentialsStore = defineStore('credentials', () => {
  const credentials = ref<NamedCredential[]>([])
  /**
   * What is on its way to the engine, and for which credential ([busy]),
   * and what the engine said when it refused the last command ([error]).
   */
  const command = useCommand<{ kind: CredentialCommand; id?: string } | null>(null)
  /** What the last command did, when it went through. */
  const notice = ref<string | null>(null)

  /** Asks the engine for the credentials. */
  const { loaded, error, load } = useLoad(async () => {
    credentials.value = (await dataOf(api.GET('/credentials'))).credentials
  })

  /** Loads again on credential events and a resync. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync' || item.event.type.startsWith('credential.')) void load()
    })
  }

  /** Runs [send] as [kind]; `true` when the engine took it, then [done] is the notice. */
  async function run(
    kind: CredentialCommand,
    id: string | undefined,
    send: () => Promise<string>,
  ): Promise<boolean> {
    notice.value = null
    const done = await command.run({ kind, id }, async () => {
      notice.value = await send()
      await load()
      return true
    })
    return done ?? false
  }

  /** Has the engine check [request] and store it under its name. */
  function create(request: CreateCredentialRequest): Promise<boolean> {
    return run('saving', undefined, async () => {
      await dataOf(api.POST('/credentials', { body: request }))
      return 'Credential saved'
    })
  }

  /** Has the engine check a new secret for the credential [id] and keep it. */
  function replace(id: string, request: ReplaceCredentialRequest): Promise<boolean> {
    return run('saving', id, async () => {
      await dataOf(
        api.PUT('/credentials/{credentialId}', { params: { path: { credentialId: id } }, body: request }),
      )
      return 'Credential saved'
    })
  }

  /** Calls the credential [id] [name]. */
  function rename(id: string, name: string): Promise<boolean> {
    return run('renaming', id, async () => {
      const renamed = await dataOf(
        api.PATCH('/credentials/{credentialId}', {
          params: { path: { credentialId: id } },
          body: { name: name.trim() },
        }),
      )
      return `Renamed to ${renamed.name}`
    })
  }

  /** Checks the credential [id] and its assignments now. */
  function verify(id: string): Promise<boolean> {
    return run('verifying', id, async () => {
      const checked = await dataOf(
        api.POST('/credentials/{credentialId}/verify', { params: { path: { credentialId: id } } }),
      )
      return `Checked ${checked.name}: ${statusOf(checked.status).label}`
    })
  }

  /** Deletes the credential [id]; [force] when flavors use it, which give it up. */
  function remove(id: string, force: boolean): Promise<boolean> {
    return run('deleting', id, async () => {
      await doneOf(
        api.DELETE('/credentials/{credentialId}', {
          params: { path: { credentialId: id }, query: force ? { force: 'true' } : {} },
        }),
      )
      return 'Credential deleted'
    })
  }

  return {
    credentials,
    loaded,
    error,
    command: command.busy,
    commandError: command.error,
    notice,
    load,
    follow,
    create,
    replace,
    rename,
    verify,
    remove,
  }
})
