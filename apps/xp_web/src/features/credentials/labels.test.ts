import { describe, expect, it } from 'vitest'

import { projectOf } from '@/testing/fixtures'

import {
  base64Of,
  flavorTargets,
  kindName,
  namedKinds,
  statusOf,
  usageLabel,
  usedByLabel,
  worstStatus,
} from './labels'

describe('credential labels', () => {
  it('names the kinds, and leaves the GitHub token out of the named ones', () => {
    expect(kindName('asc_key')).toBe('App Store Connect API key')
    expect(namedKinds).not.toContain('github')
    expect(namedKinds).toHaveLength(9)
  })

  it('says what a check found, and what several add up to', () => {
    expect(statusOf('verified').label).toBe('Verified')
    expect(statusOf('rejected').label).toBe('Rejected')
    expect(statusOf('unreachable').label).toBe('Not checked')
    expect(worstStatus([])).toBeNull()
    expect(worstStatus(['verified', 'rejected'])).toBe('rejected')
    expect(worstStatus(['verified', 'verified'])).toBe('verified')
    expect(worstStatus(['verified', 'unverified'])).toBe('unverified')
  })

  it('says how many flavors use a credential, and where', () => {
    expect(usedByLabel(0)).toBe('Not used')
    expect(usedByLabel(1)).toBe('1 flavor')
    expect(usedByLabel(3)).toBe('3 flavors')
    expect(usageLabel({ projectId: 'prj_1', project: 'acme/app', app: '.', flavor: 'dev', status: 'verified' })).toBe(
      'acme/app · dev',
    )
    expect(usageLabel({ projectId: 'prj_1', app: 'apps/b', flavor: 'prod', status: 'verified' })).toBe(
      'prj_1 · apps/b · prod',
    )
  })

  it('lists the flavors of a project, default for an app without flavors', () => {
    const project = projectOf()
    project.profile.apps.push({ ...project.profile.apps[0]!, name: 'admin', path: 'apps/admin', flavors: [] })

    expect(flavorTargets(project)).toEqual([
      { app: '.', appName: 'app', flavor: 'dev' },
      { app: '.', appName: 'app', flavor: 'prod' },
      { app: 'apps/admin', appName: 'admin', flavor: 'default' },
    ])
  })

  it('encodes the bytes of a file as base64, large ones too', () => {
    expect(base64Of(new TextEncoder().encode('FAKE').buffer as ArrayBuffer)).toBe('RkFLRQ==')
    const large = new Uint8Array(0x8000 * 2 + 5).fill(65)
    expect(atob(base64Of(large.buffer as ArrayBuffer))).toHaveLength(large.length)
  })
})
