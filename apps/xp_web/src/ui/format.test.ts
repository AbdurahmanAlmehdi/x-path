import { describe, expect, it } from 'vitest'

import { runOf } from '@/testing/fixtures'

import {
  formatCountdown,
  formatDuration,
  formatSize,
  formatTime,
  isFinished,
  originOf,
  plainText,
  pubspecLabel,
  scopeOf,
  shortSha,
  statusOf,
  stepKind,
  timeAgo,
  versionLabel,
} from './format'

describe('format', () => {
  it('names states as the Mac app does', () => {
    expect(statusOf('waiting_for_approval')).toEqual({ label: 'Waiting for approval', tone: 'attention' })
    expect(statusOf('pending').label).toBe('Queued')
  })

  it('knows which states have ended', () => {
    expect(isFinished('cancelled')).toBe(true)
    expect(isFinished('waiting_for_resume')).toBe(false)
  })

  it('names step kinds, and keeps one it does not know', () => {
    expect(stepKind('git.checkout')).toBe('Check out')
    expect(stepKind('custom.step')).toBe('custom.step')
  })

  it('writes versions with their build', () => {
    expect(versionLabel('1.2.0', 8)).toBe('1.2.0 (8)')
    expect(versionLabel('1.2.0')).toBe('1.2.0')
    expect(pubspecLabel('1.2.0+8')).toBe('1.2.0 (8)')
    expect(pubspecLabel('1.2.0')).toBe('1.2.0')
  })

  it('says what a run is for', () => {
    expect(scopeOf(runOf())).toBe('dev · android')
    expect(scopeOf({ request: undefined })).toBe('')
  })

  it('says who started a run', () => {
    expect(originOf(runOf())).toBe('Sam')
    expect(originOf({ origin: { kind: 'agent', personName: 'Sam' } })).toBe('an agent of Sam')
    expect(originOf({ origin: { kind: 'person' } })).toBe('someone')
    expect(originOf({ origin: undefined })).toBeNull()
  })

  it('writes durations as the Mac app does', () => {
    expect(formatDuration(-5)).toBe('0s')
    expect(formatDuration(400)).toBe('0.4s')
    expect(formatDuration(12_000)).toBe('12s')
    expect(formatDuration(185_000)).toBe('3m 05s')
    expect(formatDuration(3_720_000)).toBe('1h 02m')
  })

  it('says how long ago something was', () => {
    const now = Date.parse('2026-11-14T12:00:00Z')

    expect(timeAgo('2026-11-14T11:59:40Z', now)).toBe('just now')
    expect(timeAgo('2026-11-14T11:55:00Z', now)).toBe('5 minutes ago')
    expect(timeAgo('2026-11-14T09:00:00Z', now)).toBe('3 hours ago')
    expect(timeAgo('2026-11-13T12:00:00Z', now)).toBe('yesterday')
  })

  it('writes a time in full', () => {
    expect(formatTime('2026-11-14T12:00:00Z')).toMatch(/2026/)
  })

  it('drops the escape sequences of a terminal', () => {
    expect(plainText('\u001b[32mok\u001b[0m done')).toBe('ok done')
  })

  it('shortens a commit, and counts down to a deadline', () => {
    const now = Date.parse('2026-11-14T12:00:00Z')

    expect(shortSha('0123456789abcdef')).toBe('0123456')
    expect(formatCountdown('2026-11-15T11:51:00Z', now)).toBe('23h 51m')
    expect(formatCountdown('2026-11-14T12:42:30Z', now)).toBe('42m')
    expect(formatCountdown('2026-11-14T11:00:00Z', now)).toBe('0m')
  })

  it('writes a size in bytes', () => {
    expect(formatSize(512)).toBe('512 B')
    expect(formatSize(1_500_000)).toBe('1.5 MB')
    expect(formatSize(120_000_000_000)).toBe('120 GB')
    expect(formatSize(3_000_000_000_000_000)).toBe('3000 TB')
  })
})
