import { defineStore } from 'pinia'
import { ref } from 'vue'

import { api, dataOf, doneOf, failureMessage, type GitHubTokenStatus } from '@/api/client'

/** A part of the settings, each saved and refused on its own. */
export type SettingsSection = 'publicUrl' | 'runnerUrl' | 'github'

/**
 * The engine's settings: the public URL browsers sign in through (D3), the
 * runner URL pairing commands carry, and whether the engine has its GitHub
 * token. The token itself is write-only: it goes to the engine and is never
 * read back, kept or shown.
 */
export const useSettingsStore = defineStore('settings', () => {
  const publicUrl = ref<string | null>(null)
  const runnerUrl = ref<string | null>(null)
  /** Why the runner URL may be a bad idea, though the engine took it. */
  const runnerUrlWarning = ref<string | null>(null)
  const github = ref<GitHubTokenStatus | null>(null)
  const loaded = ref(false)
  /** The section on its way to the engine. */
  const saving = ref<SettingsSection | null>(null)
  /** What the engine said about each section, when it could not read or save it. */
  const errors = ref<Partial<Record<SettingsSection, string>>>({})

  function failed(section: SettingsSection, failure: unknown) {
    errors.value = { ...errors.value, [section]: failureMessage(failure) }
  }

  function cleared(section: SettingsSection) {
    const rest = { ...errors.value }
    delete rest[section]
    errors.value = rest
  }

  async function loadPublicUrl() {
    try {
      publicUrl.value = (await dataOf(api.GET('/settings/public-url'))).url ?? null
    } catch (failure) {
      failed('publicUrl', failure)
    }
  }

  async function loadRunnerUrl() {
    try {
      runnerUrl.value = (await dataOf(api.GET('/settings/runner-url'))).url ?? null
    } catch (failure) {
      failed('runnerUrl', failure)
    }
  }

  async function loadGitHub() {
    try {
      github.value = await dataOf(api.GET('/github-token'))
    } catch (failure) {
      failed('github', failure)
    }
  }

  /** Reads every setting. */
  async function load(): Promise<void> {
    errors.value = {}
    await Promise.all([loadPublicUrl(), loadRunnerUrl(), loadGitHub()])
    loaded.value = true
  }

  /** Runs [save] for [section]; `true` when the engine took it. */
  async function saved(section: SettingsSection, save: () => Promise<void>): Promise<boolean> {
    saving.value = section
    cleared(section)
    try {
      await save()
      return true
    } catch (failure) {
      failed(section, failure)
      return false
    } finally {
      saving.value = null
    }
  }

  /** Sets the public URL, or clears it with `null`. */
  function setPublicUrl(url: string | null): Promise<boolean> {
    return saved('publicUrl', async () => {
      const body = { url: url === null ? null : url.trim() }
      publicUrl.value = (await dataOf(api.PUT('/settings/public-url', { body }))).url ?? null
    })
  }

  /** Sets the runner URL, or clears it with `null`. */
  function setRunnerUrl(url: string | null): Promise<boolean> {
    return saved('runnerUrl', async () => {
      const body = { url: url === null ? null : url.trim() }
      const now = await dataOf(api.PUT('/settings/runner-url', { body }))
      runnerUrl.value = now.url ?? null
      runnerUrlWarning.value = now.warning ?? null
    })
  }

  /**
   * Hands [token] to the engine, which checks it with GitHub before it keeps
   * it. Nothing here keeps it.
   */
  function saveGitHubToken(token: string): Promise<boolean> {
    return saved('github', async () => {
      github.value = await dataOf(api.PUT('/github-token', { body: { token: token.trim() } }))
    })
  }

  /** Has the engine take the token of the GitHub CLI on its machine. */
  function importGitHubToken(): Promise<boolean> {
    return saved('github', async () => {
      github.value = await dataOf(api.POST('/github-token/import'))
    })
  }

  /** Has the engine forget its GitHub token. */
  function removeGitHubToken(): Promise<boolean> {
    return saved('github', async () => {
      await doneOf(api.DELETE('/github-token'))
      github.value = { stored: false }
    })
  }

  return {
    publicUrl,
    runnerUrl,
    runnerUrlWarning,
    github,
    loaded,
    saving,
    errors,
    load,
    loadRunnerUrl,
    setPublicUrl,
    setRunnerUrl,
    saveGitHubToken,
    importGitHubToken,
    removeGitHubToken,
  }
})
