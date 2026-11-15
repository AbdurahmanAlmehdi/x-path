import type {
  Approval,
  Release,
  ReleaseEvent,
  ReleaseState,
  ReleaseStore,
  StatusSource,
  StoreState,
  StoreStatus,
} from '@/api/client'
import { approvalStatus, approvalTitle, deciderOf } from '@/features/approvals/labels'
import { type StatusLabel, formatTime, shortSha } from '@/ui/format'

/** The stores, in the order the board shows their lanes. */
export const releaseStores: ReleaseStore[] = ['apple', 'play']

const releaseStates: Record<ReleaseState, StatusLabel> = {
  draft: { label: 'Draft', tone: 'neutral' },
  building: { label: 'Building', tone: 'info' },
  uploaded: { label: 'Uploaded', tone: 'neutral' },
  in_review: { label: 'In review', tone: 'info' },
  rejected: { label: 'Rejected', tone: 'negative' },
  approved: { label: 'Approved', tone: 'positive' },
  live: { label: 'Live', tone: 'positive' },
  merged: { label: 'Merged', tone: 'merged' },
  abandoned: { label: 'Abandoned', tone: 'neutral' },
}

/** What a release in [state] is called, with the tone of its badge. */
export function releaseStatus(state: ReleaseState): StatusLabel {
  return releaseStates[state]
}

/** Whether a release in [state] is over: merged or abandoned. */
export function isOver(state: ReleaseState): boolean {
  return state === 'merged' || state === 'abandoned'
}

/** Whether every store approved a release in [state]: its rollouts and patches can change. */
export function storesApproved(state: ReleaseState): boolean {
  return state === 'approved' || state === 'live' || state === 'merged'
}

/** What the UI calls [store]. */
export function storeName(store: ReleaseStore): string {
  return store === 'apple' ? 'App Store' : 'Google Play'
}

/** What [store] calls a release in [state], with the tone of its badge. */
export function storeStatus(store: ReleaseStore, state: StoreState): StatusLabel {
  const apple = store === 'apple'
  switch (state) {
    case 'pending':
      return { label: 'Not uploaded', tone: 'neutral' }
    case 'uploaded':
      return { label: 'Uploaded', tone: 'neutral' }
    case 'in_review':
      return { label: 'In review', tone: 'info' }
    case 'rejected':
      return { label: apple ? 'Rejected' : 'Not approved', tone: 'negative' }
    case 'approved':
      return { label: apple ? 'Pending developer release' : 'Approved · not published', tone: 'attention' }
    case 'live':
      return { label: apple ? 'Ready for sale' : 'Published', tone: 'positive' }
  }
}

/** The status of [release] in [store], if it goes there. */
export function storeOf(release: Release, store: ReleaseStore): StoreStatus | undefined {
  return release.stores.find((status) => status.store === store)
}

/** The stores of [release] in [state]. */
function storesIn(release: Release, state: StoreState): ReleaseStore[] {
  return release.stores.filter((status) => status.state === state).map((status) => status.store)
}

/** [stores] in one phrase: `App Store`, `App Store and Google Play`. */
function storeList(stores: ReleaseStore[]): string {
  return stores.length === 1 ? storeName(stores[0]!) : 'App Store and Google Play'
}

/** The `min_version_*` variable of [store] in Firebase Remote Config. */
function minVersionVariable(store: ReleaseStore): string {
  return store === 'apple' ? 'min_version_ios' : 'min_version_android'
}

/** The variables of [stores] in one phrase. */
export function variableList(stores: ReleaseStore[]): string {
  return stores.map(minVersionVariable).join(' and ')
}

/** The hero of [release]: its state, and which store rejected it or has it live. */
export function releaseHero(release: Release): string {
  const rejected = storesIn(release, 'rejected')
  const live = storesIn(release, 'live')
  if (release.state === 'rejected' && rejected.length === 1) return `Rejected by ${storeName(rejected[0]!)}`
  if (release.state === 'rejected' && rejected.length > 1) return 'Rejected by both stores'
  if (release.state === 'live' && live.length > 1) return 'Live on both stores'
  if (release.state === 'live' && live.length === 1) return `Live on ${storeName(live[0]!)}`
  return releaseStatus(release.state).label
}

/** Where a store status came from, for the timeline. */
export function statusSource(store: ReleaseStore, source: StatusSource): string {
  switch (source) {
    case 'upload':
      return 'Upload step'
    case 'api':
      return store === 'apple' ? 'App Store Connect API' : 'Google Play API'
    case 'lookup':
      return 'iTunes lookup'
    case 'manual':
      return 'Marked by hand'
  }
}

/**
 * Why Merge is not open for [release], or what it merges when it is.
 * [readsStore] says whether the engine reads a store, or it is marked by hand.
 */
export function mergeCaption(
  release: Release,
  approvals: Approval[],
  readsStore: (store: ReleaseStore) => boolean,
): string {
  const base = release.baseBranch ?? 'the base branch'
  if (release.state === 'merged') return `Merged · ${shortSha(release.mergeCommit ?? '')}`
  if (release.state === 'abandoned') return 'The release was abandoned'
  if (release.mergeEnabled) {
    return release.branch ? `${release.branch} → ${base} · both stores live` : 'Both stores live'
  }
  if (release.mergeRunId) {
    const waits = approvals.some(
      (approval) => approval.runId === release.mergeRunId && approval.state === 'pending',
    )
    return waits ? 'Merge requested · waits for your approval' : 'Merge requested'
  }
  const rejected = storesIn(release, 'rejected')
  if (rejected.length > 0) return `${storeList(rejected)} rejected this build`
  const notLive = release.stores.filter((status) => status.state !== 'live').map((status) => status.store)
  if (notLive.length === 0) {
    return release.prNumber === undefined ? 'The release has no pull request yet' : 'Both stores live'
  }
  const marks = notLive.filter((store) => !readsStore(store))
  if (marks.length === 0) {
    return notLive.length > 1 ? 'Waits for both stores to go live' : `Waits for ${storeName(notLive[0]!)} to go live`
  }
  return notLive
    .map((store) => (marks.includes(store) ? `Mark ${storeName(store)} live` : `${storeName(store)} must go live`))
    .join(' and ')
}

/** Where a step of a lane is. */
type LanePhase = 'done' | 'now' | 'todo'

/** One step of a store lane: `Uploaded`, `In review`, `Ready for sale`. */
export interface LaneStep {
  label: string
  phase: LanePhase
  time?: string
}

function phaseOf(index: number, reached: number): LanePhase {
  return index < reached ? 'done' : index === reached ? 'now' : 'todo'
}

/**
 * The steps of a lane in [status]. A store the engine reads ([manual] is
 * false) shows its review; one it cannot read shows what it cannot know.
 */
export function laneSteps(status: StoreStatus, manual: boolean): LaneStep[] {
  const { store, state, changedAt } = status
  const since = changedAt ? `since ${formatTime(changedAt)}` : undefined
  const at = changedAt ? formatTime(changedAt) : undefined
  const live = storeStatus(store, 'live').label
  if (state === 'rejected') {
    return [
      { label: 'Uploaded', phase: 'done' },
      { label: 'In review', phase: 'done' },
      { label: storeStatus(store, state).label, phase: 'now', time: at },
    ]
  }
  if (manual) {
    const reached = state === 'pending' ? -1 : state === 'live' ? 2 : 1
    const middle = state === 'approved' ? 'Approved' : 'Unknown'
    const noReader = store === 'apple' ? 'no API key' : 'no service account'
    return ['Uploaded', middle, live].map((label, index) => ({
      label,
      phase: phaseOf(index, reached),
      time:
        index !== reached
          ? undefined
          : index === 1 && state !== 'approved'
            ? noReader
            : index === 2
              ? at
              : since,
    }))
  }
  const review = store === 'apple' && status.detail === 'WAITING_FOR_REVIEW' ? 'Waiting for review' : 'In review'
  const order: StoreState[] = ['uploaded', 'in_review', 'approved', 'live']
  const reached = order.indexOf(state)
  return ['Uploaded', review, 'Approved', live].map((label, index) => ({
    label,
    phase: phaseOf(index, reached),
    time: index !== reached ? undefined : index === 3 ? at : since,
  }))
}

/** The newest release of the same app and flavor as [release], other than it, that is live in [store]. */
export function liveBefore(releases: Release[], release: Release, store: ReleaseStore): Release | undefined {
  return releases.find(
    (other) =>
      other.id !== release.id &&
      other.app === release.app &&
      other.flavor === release.flavor &&
      storeOf(other, store)?.state === 'live',
  )
}

/** One line of the timeline of a release. */
export interface TimelineEntry {
  status: StatusLabel
  title: string
  detail?: string
  at: string
}

const draft = releaseStatus('draft')
const building = releaseStatus('building')
const asked = approvalStatus('pending')
const liveTone = releaseStatus('live')

function storeLine(store: ReleaseStore, wire: string | undefined): Pick<TimelineEntry, 'status' | 'title'> {
  const states: StoreState[] = ['pending', 'uploaded', 'in_review', 'rejected', 'approved', 'live']
  const state = states.find((each) => each === wire)
  if (!state) return { status: draft, title: `${storeName(store)}: ${wire ?? ''}` }
  const status = storeStatus(store, state)
  return { status, title: `${storeName(store)}: ${status.label.toLowerCase()}` }
}

function entryOf(release: Release, event: ReleaseEvent): TimelineEntry {
  const number = event.patchNumber ?? 0
  const base = release.baseBranch ?? 'the base branch'
  let line: Pick<TimelineEntry, 'status' | 'title'> & { detail?: string }
  switch (event.kind) {
    case 'created':
      line = { status: draft, title: 'Release dispatched', detail: release.flavor }
      break
    case 'build':
      line = { status: building, title: `Build ${event.detail ?? ''} started` }
      break
    case 'store':
      // A store change says which store; one from a newer engine may not.
      line = event.store ? storeLine(event.store, event.detail) : { status: draft, title: event.detail ?? '' }
      break
    case 'merge_requested':
      line = { status: asked, title: 'Merge requested' }
      break
    case 'merged':
      line = {
        status: releaseStatus('merged'),
        title: `Merged into ${base}`,
        detail: event.detail ? shortSha(event.detail) : undefined,
      }
      break
    case 'abandoned':
      line = { status: releaseStatus('abandoned'), title: 'Abandoned', detail: event.detail }
      break
    case 'rollout_requested':
      line = { status: asked, title: 'Rollout change requested' }
      break
    case 'rollout':
      line = {
        status: liveTone,
        title: event.store ? `${storeName(event.store)} rollout changed` : 'Rollout changed',
        detail: event.detail,
      }
      break
    case 'patch':
      line = { status: liveTone, title: `Patch ${number} published`, detail: event.detail }
      break
    case 'patch_requested':
      line = {
        status: asked,
        title:
          event.detail === 'rollback'
            ? `Rollback of patch ${number} requested`
            : `Promotion of patch ${number} requested`,
      }
      break
    case 'patch_promoted':
      line = { status: liveTone, title: `Patch ${number} promoted to stable` }
      break
    case 'patch_rolled_back':
      line = { status: releaseStatus('rejected'), title: `Patch ${number} rolled back` }
      break
    case 'texts':
      line = { status: draft, title: 'Store texts changed' }
      break
  }
  const detail = [line.detail, event.by].filter(Boolean).join(' · ')
  return { status: line.status, title: line.title, detail: detail || undefined, at: event.at }
}

/** [entries] newest first; of two at the same time, the one later in [entries] first. */
function newestFirst(entries: TimelineEntry[]): TimelineEntry[] {
  return entries
    .map((entry, index) => ({ entry, index }))
    .sort((a, b) => Date.parse(b.entry.at) - Date.parse(a.entry.at) || b.index - a.index)
    .map(({ entry }) => entry)
}

/**
 * What happened to [release], newest first: its [history] and the
 * approvals of its runs. A release from before the engine kept a history
 * shows what the release itself keeps: its dispatch and builds, the last
 * change in each store and its end.
 */
export function releaseTimeline(
  release: Release,
  approvals: Approval[],
  history: ReleaseEvent[] = [],
): TimelineEntry[] {
  const runs = new Set<string>([
    ...release.builds.map((build) => build.runId),
    ...(release.mergeRunId ? [release.mergeRunId] : []),
    ...history.flatMap((event) => (event.runId ? [event.runId] : [])),
  ])
  const approvalEntries = approvals
    .filter((approval) => approval.runId !== undefined && runs.has(approval.runId))
    .flatMap((approval): TimelineEntry[] => {
      const title = approvalTitle(approval)
      const requested: TimelineEntry = {
        status: asked,
        title: `Approval requested: ${title}`,
        detail: shortSha(approval.sha),
        at: approval.createdAt,
      }
      if (approval.state === 'pending') return [requested]
      const status = approvalStatus(approval.state)
      return [
        requested,
        {
          status,
          title: `${title}: ${status.label.toLowerCase()}`,
          detail: approval.decidedBy ? deciderOf(approval) : approval.reason,
          at: approval.decidedAt ?? approval.expiresAt,
        },
      ]
    })
  if (history.length > 0) {
    return newestFirst([...history.map((event) => entryOf(release, event)), ...approvalEntries])
  }
  const entries: TimelineEntry[] = [
    { status: draft, title: 'Release dispatched', detail: release.flavor, at: release.createdAt },
    ...release.builds.map((build) => ({
      status: building,
      title: `Build ${build.build} started`,
      at: build.createdAt,
    })),
    ...release.stores.flatMap((status) =>
      status.changedAt
        ? [
            {
              ...storeLine(status.store, status.state),
              detail: statusSource(status.store, status.source),
              at: status.changedAt,
            },
          ]
        : [],
    ),
    ...approvalEntries,
  ]
  if (release.state === 'merged') {
    entries.push({
      status: releaseStatus('merged'),
      title: `Merged into ${release.baseBranch ?? 'the base branch'}`,
      detail: release.mergeCommit ? shortSha(release.mergeCommit) : undefined,
      at: release.updatedAt,
    })
  }
  if (release.state === 'abandoned') {
    entries.push({
      status: releaseStatus('abandoned'),
      title: 'Abandoned',
      detail: release.message,
      at: release.updatedAt,
    })
  }
  return newestFirst(entries)
}

/** Where a Shorebird patch of a release is, from its history. */
export type PatchState = 'published' | 'promoted' | 'rolledBack'

/** The Shorebird patches of a release, lowest first, each where its last change in [history] left it. */
export function releasePatches(history: ReleaseEvent[]): Array<{ number: number; state: PatchState }> {
  const patches = new Map<number, PatchState>()
  for (const event of history) {
    const number = event.patchNumber
    if (number === undefined) continue
    if (event.kind === 'patch') patches.set(number, patches.get(number) ?? 'published')
    else if (event.kind === 'patch_promoted') patches.set(number, 'promoted')
    else if (event.kind === 'patch_rolled_back') patches.set(number, 'rolledBack')
  }
  return [...patches.entries()]
    .sort(([a], [b]) => a - b)
    .map(([number, state]) => ({ number, state }))
}

/**
 * The `min_version_*` reminder: when to raise the minimum version in
 * Firebase Remote Config if the release is a forced update. The engine
 * does not know whether it is one, so the copy says "if".
 */
export function minVersionText(release: Release): string {
  const stores = release.stores.map((status) => status.store)
  if (stores.length === 0) return 'This release goes to no store.'
  const live = storesIn(release, 'live')
  if (live.length === 0) {
    return `If this release is a forced update, raise ${variableList(stores)} to ${release.version} once the stores have it live. Raising it earlier locks out users who have nothing to update to.`
  }
  const later = stores.filter((store) => !live.includes(store))
  const now = `${storeList(live)} live: if this release is a forced update, raise ${variableList(live)} to ${release.version} in Firebase Remote Config now.`
  return later.length === 0
    ? now
    : `${now} Raise ${variableList(later)} once ${storeList(later)} is live.`
}
