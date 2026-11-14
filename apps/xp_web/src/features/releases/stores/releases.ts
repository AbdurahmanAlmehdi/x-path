import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  api,
  dataOf,
  failureMessage,
  type Approval,
  type Credential,
  type PatchAction,
  type Release,
  type ReleaseEvent,
  type ReleaseNotes,
  type ReleaseState,
  type ReleaseStore,
  type ReleaseTexts,
  type RolloutRequest,
  type Run,
} from '@/api/client'
import { followEvents, payloadValue } from '@/api/sockets'
import { coalesced } from '@/app/coalesce'

/** The states of a release that is under way, which the board shows first. */
export const inFlightStates: ReleaseState[] = [
  'draft',
  'building',
  'uploaded',
  'in_review',
  'rejected',
  'approved',
]

/** What the board is sending to the engine. */
export type ReleaseCommand =
  | 'refreshing'
  | 'marking'
  | 'merging'
  | 'rollingOut'
  | 'savingTexts'
  | 'movingPatch'
  | 'building'

/** What the board says once a command went through. */
const doneNotices: Partial<Record<ReleaseCommand, string>> = {
  marking: 'Store status saved',
  merging: 'Merge requested: approve it to merge',
  rollingOut: 'Rollout change requested: approve it to apply',
  savingTexts: 'Store texts saved',
  movingPatch: 'Patch change requested: approve it to apply',
}

/**
 * The releases of a project: the release shown with its stores, notes and
 * history, the approvals of the project for its timeline, and what can be
 * asked for it (refresh, the manual store marks, the rollout, a new build,
 * merge, the texts and the Shorebird patches), kept up to date by the
 * release and approval events of the project.
 */
export const useReleasesStore = defineStore('releases', () => {
  const projectId = ref<string | null>(null)
  /** The releases of the project, newest first. */
  const releases = ref<Release[]>([])
  const loaded = ref(false)
  const error = ref<string | null>(null)
  /** The release picked, if any. */
  const selectedId = ref<string | null>(null)
  /** The approvals of the project, for the timeline. */
  const approvals = ref<Approval[]>([])
  /** The credentials of the project: a store without its API credential is marked by hand. */
  const credentials = ref<Credential[]>([])
  const notes = ref<ReleaseNotes | null>(null)
  const notesError = ref<string | null>(null)
  /** What happened to the release shown, oldest first. */
  const history = ref<ReleaseEvent[]>([])
  const command = ref<ReleaseCommand | null>(null)
  /** What the engine said when the last command failed. */
  const commandError = ref<string | null>(null)
  /** What the last command did, when it went through. */
  const notice = ref<string | null>(null)
  /** The release and commit the notes were read for. */
  let notesOf: string | null = null

  /** The release shown: the one picked, else the newest in flight, else the newest. */
  const release = computed<Release | null>(
    () =>
      releases.value.find((each) => each.id === selectedId.value) ??
      releases.value.find((each) => inFlightStates.includes(each.state)) ??
      releases.value[0] ??
      null,
  )

  /**
   * Whether the engine reads [store] for [shown] through its API: its
   * flavor has an App Store Connect key or a Play service account.
   */
  function readsStore(shown: Release, store: ReleaseStore): boolean {
    const kind = store === 'apple' ? 'asc_key' : 'play_sa'
    return credentials.value.some(
      (credential) =>
        credential.kind === kind && credential.app === shown.app && credential.flavor === shown.flavor,
    )
  }

  async function loadNotes(shown: Release) {
    try {
      const read = await dataOf(api.GET('/releases/{id}/notes', { params: { path: { id: shown.id } } }))
      if (release.value?.id === shown.id) notes.value = read
    } catch (failure) {
      if (release.value?.id === shown.id) notesError.value = failureMessage(failure)
    }
  }

  async function loadHistory(shown: Release) {
    try {
      const read = await dataOf(api.GET('/releases/{id}/history', { params: { path: { id: shown.id } } }))
      if (release.value?.id === shown.id) history.value = read.events
    } catch {
      // The timeline keeps what it showed; the next change reads again.
    }
  }

  /** Reads the history of the release shown, and its notes when it or its commit changed. */
  async function loadShown() {
    const shown = release.value
    if (!shown) return
    const key = shown.headSha ? `${shown.id}@${shown.headSha}` : null
    const reads = [loadHistory(shown)]
    if (key !== notesOf) {
      notesOf = key
      notes.value = null
      notesError.value = null
      if (key) reads.push(loadNotes(shown))
    }
    await Promise.all(reads)
  }

  async function loadReleases(project: string) {
    try {
      const read = await dataOf(api.GET('/releases', { params: { query: { project } } }))
      if (projectId.value !== project) return
      const before = release.value?.id
      releases.value = read.releases
      error.value = null
      if (release.value?.id !== before) history.value = []
    } catch (failure) {
      if (projectId.value === project) error.value = failureMessage(failure)
    } finally {
      if (projectId.value === project) loaded.value = true
    }
  }

  async function loadApprovals(project: string) {
    try {
      const read = await dataOf(api.GET('/approvals', { params: { query: { project } } }))
      if (projectId.value === project) approvals.value = read.approvals
    } catch {
      // The timeline goes without them.
    }
  }

  async function loadCredentials(project: string) {
    try {
      const read = await dataOf(
        api.GET('/projects/{id}/credentials', { params: { path: { id: project } } }),
      )
      if (projectId.value === project) credentials.value = read.credentials
    } catch {
      // Without them every store reads as marked by hand.
    }
  }

  const refreshReleases = coalesced(async () => {
    if (!projectId.value) return
    await loadReleases(projectId.value)
    await loadShown()
  })
  const refreshApprovals = coalesced(async () => {
    if (!projectId.value) return
    await loadApprovals(projectId.value)
    // A decided approval lets a run change the release, which its history tells.
    await loadShown()
  })

  /** Shows the releases of [project], with [releaseId] if given, else the one in flight. */
  async function open(project: string, releaseId: string | null = null): Promise<void> {
    if (projectId.value !== project) {
      projectId.value = project
      releases.value = []
      approvals.value = []
      credentials.value = []
      loaded.value = false
      error.value = null
    }
    select(releaseId)
    await Promise.all([loadReleases(project), loadApprovals(project), loadCredentials(project)])
    await loadShown()
  }

  /** Shows [releaseId]; `null` shows the one in flight. */
  function select(releaseId: string | null) {
    const before = release.value?.id
    selectedId.value = releaseId
    commandError.value = null
    notice.value = null
    if (release.value?.id !== before) {
      history.value = []
      void loadShown()
    }
  }

  /** Follows the release, approval and credential events of the project. Returns the function that stops. */
  function follow(): () => void {
    return followEvents((item) => {
      if (item.kind === 'resync') {
        void refreshReleases()
        void refreshApprovals()
        if (projectId.value) void loadCredentials(projectId.value)
        return
      }
      const { type } = item.event
      if (payloadValue(item.event, 'projectId') !== projectId.value) return
      if (type.startsWith('release.')) void refreshReleases()
      else if (type.startsWith('approval.')) void refreshApprovals()
      else if (type.startsWith('credential.') && projectId.value) void loadCredentials(projectId.value)
    })
  }

  /**
   * Sends [kind] for the release shown. What it answers, or `null` when
   * it failed, with [commandError] saying why.
   */
  async function send<T>(
    kind: ReleaseCommand,
    call: (id: string) => Promise<{ data?: T; error?: unknown; response: Response }>,
  ): Promise<T | null> {
    const shown = release.value
    if (!shown || command.value) return null
    command.value = kind
    commandError.value = null
    notice.value = null
    try {
      const answer = await dataOf(call(shown.id))
      notice.value = doneNotices[kind] ?? null
      void refreshReleases()
      return answer
    } catch (failure) {
      commandError.value = failureMessage(failure)
      return null
    } finally {
      command.value = null
    }
  }

  const path = (id: string) => ({ params: { path: { id } } })

  /** Asks the stores about the release now. */
  const refresh = () => send('refreshing', (id) => api.POST('/releases/{id}/refresh', path(id)))

  /** Says by hand that [store] is in [state]. */
  const mark = (store: ReleaseStore, state: 'approved' | 'live') =>
    send('marking', (id) =>
      api.POST('/releases/{id}/stores/{store}/status', {
        params: { path: { id, store } },
        body: { state },
      }),
    )

  /** Asks to merge the release pull request; the merge waits for an approval. */
  const merge = () => send('merging', (id) => api.POST('/releases/{id}/merge', path(id)))

  /** Asks to change the rollout in a store; the change waits for an approval. */
  const rollout = (request: RolloutRequest) =>
    send('rollingOut', (id) => api.POST('/releases/{id}/rollout', { ...path(id), body: request }))

  /** Builds the rejected version again with a new build number: the run that does. */
  const newBuild = (): Promise<Run | null> =>
    send('building', (id) => api.POST('/releases/{id}/builds', path(id)))

  /** Saves the texts the uploads of the release send. */
  const saveTexts = (texts: ReleaseTexts) =>
    send('savingTexts', (id) => api.PUT('/releases/{id}/texts', { ...path(id), body: texts }))

  /** Asks to promote or roll back the Shorebird patch [number]; the change waits for an approval. */
  async function movePatch(number: number, action: PatchAction) {
    const run = await send('movingPatch', (id) =>
      api.POST('/releases/{id}/patches/{number}/{action}', {
        params: { path: { id, number: String(number), action } },
      }),
    )
    void loadShown()
    return run
  }

  return {
    projectId,
    releases,
    loaded,
    error,
    selectedId,
    approvals,
    credentials,
    notes,
    notesError,
    history,
    command,
    commandError,
    notice,
    release,
    readsStore,
    open,
    select,
    follow,
    refresh,
    mark,
    merge,
    rollout,
    newBuild,
    saveTexts,
    movePatch,
  }
})
