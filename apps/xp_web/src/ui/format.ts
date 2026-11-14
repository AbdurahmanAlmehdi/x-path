import type { JobState, Run, RunState, StepState } from '@/api/client'

/** How a state reads, with the tone of its badge. */
export interface StatusLabel {
  label: string
  tone: 'neutral' | 'info' | 'attention' | 'positive' | 'negative' | 'caution' | 'merged'
}

const states: Record<JobState | RunState | StepState, StatusLabel> = {
  queued: { label: 'Queued', tone: 'neutral' },
  pending: { label: 'Queued', tone: 'neutral' },
  running: { label: 'Running', tone: 'info' },
  waiting_for_approval: { label: 'Waiting for approval', tone: 'attention' },
  waitingForApproval: { label: 'Waiting for approval', tone: 'attention' },
  waiting_for_resume: { label: 'Waiting for a resume', tone: 'caution' },
  succeeded: { label: 'Succeeded', tone: 'positive' },
  failed: { label: 'Failed', tone: 'negative' },
  cancelled: { label: 'Cancelled', tone: 'neutral' },
  interrupted: { label: 'Interrupted', tone: 'caution' },
  skipped: { label: 'Skipped · already done', tone: 'neutral' },
}

/** What a run, job or step in [state] is called, as the Mac app says it. */
export function statusOf(state: JobState | RunState | StepState): StatusLabel {
  return states[state]
}

/** The run states, in the order the filters offer them. */
export const runStates: RunState[] = [
  'queued',
  'running',
  'waiting_for_approval',
  'succeeded',
  'failed',
  'cancelled',
]

/** Whether a job in [state] has ended for good, or until a resume. */
export function isFinished(state: JobState | RunState): boolean {
  return ['succeeded', 'failed', 'cancelled'].includes(state)
}

const stepKinds: Record<string, string> = {
  'git.checkout': 'Check out',
  guard: 'Checks',
  'version.bump': 'Bump version',
  'build.android': 'Build Android',
  'build.ios': 'Build iOS',
  'build.verifyCompiledConfig': 'Verify compiled config',
  'ios.stripAndReexport': 'Strip and re-export IPA',
  'shorebird.release': 'Shorebird release',
  'shorebird.patch': 'Shorebird patch',
  'symbols.archive': 'Archive symbols',
  test: 'Tests',
  analyze: 'Analyze',
  'upload.appStore': 'Upload to App Store',
  'upload.play': 'Upload to Google Play',
  'upload.firebase': 'Upload to Firebase',
  'git.tag': 'Tag',
  'git.push': 'Push',
  'git.releaseBranch': 'Cut the release branch',
  'github.createPr': 'Open the release PR',
  'github.mergePr': 'Merge the release PR',
  'store.rollout': 'Change the rollout',
  'shorebird.track': 'Move a Shorebird patch',
  'record.manifest': 'Record the manifest',
  gate: 'Approval',
  command: 'Command',
}

/** What the UI calls a step of [kind]; the kind itself for one it does not know. */
export function stepKind(kind: string): string {
  return stepKinds[kind] ?? kind
}

/** A version with its build number: `5.4.1 (3283)`. */
export function versionLabel(version: string, build?: number): string {
  return build === undefined ? version : `${version} (${build})`
}

/** A pubspec version (`5.5.0+3284`) as the UI writes it: `5.5.0 (3284)`. */
export function pubspecLabel(pubspec: string): string {
  const [name, ...rest] = pubspec.split('+')
  return rest.length === 0 ? pubspec : `${name} (${rest.join('+')})`
}

/** What a run is for: its flavors and platforms, `dev · android`. */
export function scopeOf(run: Pick<Run, 'request'>): string {
  return [...(run.request?.flavors ?? []), ...(run.request?.platforms ?? [])].join(' · ')
}

/** Who started a run: the person, or an agent on their behalf. */
export function originOf(run: Pick<Run, 'origin'>): string | null {
  const origin = run.origin
  if (!origin) return null
  const name = origin.personName ?? 'someone'
  return origin.kind === 'agent' ? `an agent of ${name}` : name
}

/** A duration as the Mac app writes it: `0.4s`, `12s`, `3m 05s`, `1h 02m`. */
export function formatDuration(milliseconds: number): string {
  if (milliseconds < 0) return '0s'
  if (milliseconds < 1000) return `${(milliseconds / 1000).toFixed(1)}s`
  const seconds = Math.floor(milliseconds / 1000)
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor(seconds / 60) % 60
  const pad = (value: number) => String(value).padStart(2, '0')
  if (hours > 0) return `${hours}h ${pad(minutes)}m`
  if (minutes > 0) return `${minutes}m ${pad(seconds % 60)}s`
  return `${seconds}s`
}

const relative = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })

/** When [at] was, from [now]: `just now`, `5 minutes ago`, `yesterday`. */
export function timeAgo(at: string, now = Date.now()): string {
  const seconds = Math.round((Date.parse(at) - now) / 1000)
  if (Math.abs(seconds) < 45) return 'just now'
  const minutes = Math.round(seconds / 60)
  if (Math.abs(minutes) < 60) return relative.format(minutes, 'minute')
  const hours = Math.round(minutes / 60)
  if (Math.abs(hours) < 24) return relative.format(hours, 'hour')
  return relative.format(Math.round(hours / 24), 'day')
}

/** [at] in full, in the browser's time zone. */
export function formatTime(at: string): string {
  return new Date(at).toLocaleString('en', { dateStyle: 'medium', timeStyle: 'short' })
}

// The escape sequences of a terminal (colours, cursor moves) in a log line.
const ansi = new RegExp('\\u001b\\[[0-9;?]*[ -/]*[@-~]', 'g')

/** A log line without the terminal's escape sequences. */
export function plainText(text: string): string {
  return text.replace(ansi, '')
}

/** The short form of a commit: its first seven characters. */
export function shortSha(sha: string): string {
  return sha.slice(0, 7)
}

/** What is left until [deadline], for an expiry: `23h 51m`, `42m`, `0m`. */
export function formatCountdown(deadline: string, now = Date.now()): string {
  const minutes = Math.max(0, Math.floor((Date.parse(deadline) - now) / 60_000))
  const hours = Math.floor(minutes / 60)
  return hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m`
}

/** A size in bytes as the Mac app writes it: `512 B`, `1.5 MB`, `120 GB`. */
export function formatSize(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let unit = 0
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000
    unit++
  }
  const number = unit === 0 || value >= 100 ? String(Math.round(value)) : value.toFixed(1)
  return `${number} ${units[unit]}`
}
