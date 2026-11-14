import type { Approval, ApprovalState, Project, Release } from '@/api/client'
import { type StatusLabel, formatCountdown, formatTime, pubspecLabel, shortSha } from '@/ui/format'

const states: Record<ApprovalState, StatusLabel> = {
  pending: { label: 'Pending', tone: 'attention' },
  approved: { label: 'Approved', tone: 'positive' },
  denied: { label: 'Denied', tone: 'negative' },
  expired: { label: 'Expired', tone: 'neutral' },
}

/** What an approval in [state] is called, with the tone of its badge. */
export function approvalStatus(state: ApprovalState): StatusLabel {
  return states[state]
}

const gateActions: Record<string, string> = {
  prod_release: 'production release',
  prod_patch: 'production patch',
  store_submission: 'store submission',
  push: 'push',
  merge: 'merge',
  rollout: 'rollout change',
  delete: 'delete',
}

/** What the UI calls the gated [action]: `store_submission` → "store submission". */
export function gateAction(action: string): string {
  return gateActions[action] ?? action
}

/** What [approval] asks for, in one line: `Submit 5.4.1 (3283) to the stores`. */
export function approvalTitle(approval: Pick<Approval, 'action' | 'version'>): string {
  const action = gateAction(approval.action)
  if (!approval.version) return `Approve the ${action}`
  const version = pubspecLabel(approval.version)
  switch (approval.action) {
    case 'prod_release':
      return `Release ${version} to the stores`
    case 'prod_patch':
      return `Patch ${version}`
    case 'store_submission':
      return `Submit ${version} to the stores`
    case 'push':
      return `Push ${version} to GitHub`
    case 'merge':
      return `Merge the release PR of ${version}`
    default:
      return `Approve the ${action} of ${version}`
  }
}

/** Who decided [approval]: the person, else the device, else "another device". */
export function deciderOf(approval: Pick<Approval, 'decidedBy'>): string {
  return approval.decidedBy?.personName ?? approval.decidedBy?.name ?? 'another device'
}

/** Whether less than an hour is left: the countdown turns `caution`. */
export function expiresSoon(approval: Pick<Approval, 'expiresAt'>, now = Date.now()): boolean {
  return Date.parse(approval.expiresAt) - now < 3_600_000
}

/** The line next to the badge: the countdown while it waits, else when and by whom it ended. */
export function approvalStateLine(approval: Approval, now = Date.now()): string {
  switch (approval.state) {
    case 'pending':
      return `expires in ${formatCountdown(approval.expiresAt, now)}`
    case 'expired':
      return `expired ${formatTime(approval.decidedAt ?? approval.expiresAt)}`
    default:
      return `by ${deciderOf(approval)} · ${formatTime(approval.decidedAt ?? approval.createdAt)}`
  }
}

/** The flavor [release] builds, as the scan of [project] describes it. */
export function flavorOf(project: Project | undefined, release: Release | null | undefined) {
  if (!project || !release) return undefined
  return project.profile.apps
    .find((app) => app.path === release.app)
    ?.flavors.find((flavor) => flavor.name === release.flavor)
}

/** What happens if [approval] is approved ("If you approve"). */
export function approvalConsequence(
  approval: Pick<Approval, 'action' | 'sha' | 'version'>,
  target: { flavor?: string; bundleId?: string; baseBranch?: string } = {},
): string {
  const sha = shortSha(approval.sha)
  const version = approval.version ? pubspecLabel(approval.version) : sha
  let text: string
  let shipped = false
  switch (approval.action) {
    case 'prod_release':
      text = `XPath builds ${version} from ${sha} and releases it to the stores.`
      shipped = true
      break
    case 'prod_patch':
      text = `XPath publishes a Shorebird patch of ${version} built from ${sha}.`
      shipped = true
      break
    case 'store_submission':
      text = `XPath uploads the builds made from ${sha} and submits ${version} for store review.`
      shipped = true
      break
    case 'push':
      text = `XPath pushes the release commit ${sha} and the tag of ${version} to GitHub.`
      break
    case 'merge':
      text = `XPath merges the release pull request of ${version} into ${target.baseBranch ?? 'the base branch'} with a merge commit.`
      break
    case 'delete':
      text = `XPath deletes what the job asks to delete, on ${sha}.`
      break
    default:
      text = `The job goes on with its ${gateAction(approval.action)}.`
  }
  const where = [target.flavor, target.bundleId].filter(Boolean).join(' · ')
  return shipped && where ? `${text} It goes out as ${where}.` : text
}
