import type { PairingToken, Runner } from '@/api/client'
import type { StatusLabel } from '@/ui/format'

/**
 * What a runner is doing, as the Mac app says it: online and idle, busy,
 * draining before an update, lost mid-job (offline with jobs), offline,
 * revoked.
 */
export function runnerStatus(runner: Runner): StatusLabel {
  switch (runner.status) {
    case 'online':
      return runner.jobIds.length === 0
        ? { label: 'Online · idle', tone: 'positive' }
        : { label: `Online · busy ${runner.jobIds.length}/${runner.slots}`, tone: 'info' }
    case 'draining':
      return { label: 'Draining', tone: 'attention' }
    case 'offline':
      return runner.jobIds.length > 0
        ? { label: 'Lost mid-job', tone: 'negative' }
        : { label: 'Offline', tone: 'neutral' }
    case 'revoked':
      return { label: 'Revoked', tone: 'neutral' }
  }
}

/** What the machine said about itself: `macos · arm64 · xp 1.0.0 · 12 cores`. */
export function runnerMachine(runner: Runner): string {
  return [
    runner.os,
    runner.arch,
    runner.version ? `xp ${runner.version}` : undefined,
    runner.cores ? `${runner.cores} cores` : undefined,
  ]
    .filter(Boolean)
    .join(' · ')
}

const loopbackHosts = ['localhost', '127.0.0.1', '[::1]']

/** The command a new runner machine runs to pair, and whether it only works on the engine's machine. */
export interface PairingCommand {
  text: string
  /** No runner URL is set, and the page reaches the engine on loopback. */
  onlyHere: boolean
}

/**
 * The pairing command of [token]: the runner URL it carries, else
 * [runnerUrl] (one set since), else [origin], where this page reaches the
 * engine.
 */
export function pairingCommand(token: PairingToken, origin: string, runnerUrl?: string): PairingCommand {
  const engine = token.engineUrl ?? runnerUrl ?? origin.replace(/\/+$/, '')
  return {
    text: `xp runner pair --engine ${engine} --token ${token.token}`,
    onlyHere:
      token.engineUrl === undefined &&
      runnerUrl === undefined &&
      loopbackHosts.includes(new URL(origin).hostname),
  }
}
