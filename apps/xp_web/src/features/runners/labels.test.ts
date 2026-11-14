import { describe, expect, it } from 'vitest'

import { runnerOf } from '@/testing/fixtures'

import { pairingCommand, runnerMachine, runnerStatus } from './labels'

describe('runnerStatus', () => {
  it('says what a runner does, as the Mac app says it', () => {
    expect(runnerStatus(runnerOf())).toEqual({ label: 'Online · idle', tone: 'positive' })
    expect(runnerStatus(runnerOf({ jobIds: ['job_1'] })).label).toBe('Online · busy 1/2')
    expect(runnerStatus(runnerOf({ status: 'draining' })).label).toBe('Draining')
    expect(runnerStatus(runnerOf({ status: 'offline', jobIds: ['job_1'] })).label).toBe('Lost mid-job')
    expect(runnerStatus(runnerOf({ status: 'offline' })).label).toBe('Offline')
    expect(runnerStatus(runnerOf({ status: 'revoked' })).label).toBe('Revoked')
  })
})

describe('runnerMachine', () => {
  it('says what the machine reported, leaving out what it did not', () => {
    expect(runnerMachine(runnerOf())).toBe('macos · arm64 · xp 1.4.0 · 10 cores')
    expect(runnerMachine(runnerOf({ os: undefined, version: undefined, cores: undefined }))).toBe('arm64')
  })
})

describe('pairingCommand', () => {
  const token = { token: 'xpp_fake', name: 'mac-mini', expiresAt: '2026-11-14T09:15:00Z' }

  it('names the runner URL the token carries', () => {
    const command = pairingCommand({ ...token, engineUrl: 'https://xp.tail.ts.net' }, 'http://127.0.0.1:7480')

    expect(command).toEqual({
      text: 'xp runner pair --engine https://xp.tail.ts.net --token xpp_fake',
      onlyHere: false,
    })
  })

  it('takes a runner URL set since, else where the page reaches the engine', () => {
    expect(pairingCommand(token, 'http://127.0.0.1:7480', 'http://mac-mini.local:7480').text).toContain(
      '--engine http://mac-mini.local:7480 ',
    )
    expect(pairingCommand(token, 'https://xpath.example.com/')).toEqual({
      text: 'xp runner pair --engine https://xpath.example.com --token xpp_fake',
      onlyHere: false,
    })
  })

  it('says when the address only works on the engine machine', () => {
    expect(pairingCommand(token, 'http://localhost:7480').onlyHere).toBe(true)
    expect(pairingCommand(token, 'http://[::1]:7480').onlyHere).toBe(true)
  })
})
