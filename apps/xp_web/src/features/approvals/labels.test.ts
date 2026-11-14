import { describe, expect, it } from 'vitest'

import { approvalOf, projectOf, releaseOf } from '@/testing/fixtures'

import {
  approvalConsequence,
  approvalStateLine,
  approvalStatus,
  approvalTitle,
  deciderOf,
  expiresSoon,
  flavorOf,
  gateAction,
} from './labels'

describe('approval labels', () => {
  const now = Date.parse('2026-11-14T10:00:00Z')

  it('names states and gates as the Mac app does', () => {
    expect(approvalStatus('pending')).toEqual({ label: 'Pending', tone: 'attention' })
    expect(approvalStatus('denied').tone).toBe('negative')
    expect(gateAction('store_submission')).toBe('store submission')
    expect(gateAction('rollout')).toBe('rollout change')
    expect(gateAction('later_gate')).toBe('later_gate')
  })

  it('says what an approval asks for', () => {
    const titles = ['prod_release', 'prod_patch', 'store_submission', 'push', 'merge', 'rollout'].map(
      (action) => approvalTitle({ action: action as never, version: '1.2.0+8' }),
    )
    expect(titles).toEqual([
      'Release 1.2.0 (8) to the stores',
      'Patch 1.2.0 (8)',
      'Submit 1.2.0 (8) to the stores',
      'Push 1.2.0 (8) to GitHub',
      'Merge the release PR of 1.2.0 (8)',
      'Approve the rollout change of 1.2.0 (8)',
    ])
    expect(approvalTitle({ action: 'prod_release' })).toBe('Approve the production release')
  })

  it('names who decided: the person, else the device, else another device', () => {
    const decidedBy = { tokenId: 'tok_1', name: 'Mac mini', kind: 'app' as const }
    expect(deciderOf({ decidedBy: { ...decidedBy, personName: 'Sam' } })).toBe('Sam')
    expect(deciderOf({ decidedBy })).toBe('Mac mini')
    expect(deciderOf({})).toBe('another device')
  })

  it('counts down while it waits, and says how it ended', () => {
    expect(approvalStateLine(approvalOf(), now)).toBe('expires in 23h 0m')
    expect(expiresSoon(approvalOf(), now)).toBe(false)
    expect(expiresSoon(approvalOf({ expiresAt: '2026-11-14T10:30:00Z' }), now)).toBe(true)
    expect(approvalStateLine(approvalOf({ state: 'expired' }), now)).toMatch(/^expired Nov 15, 2026/)
    expect(
      approvalStateLine(
        approvalOf({
          state: 'approved',
          decidedAt: '2026-11-14T09:30:00Z',
          decidedBy: { tokenId: 'tok_1', name: 'Browser', kind: 'web', personName: 'Sam' },
        }),
        now,
      ),
    ).toMatch(/^by Sam · Nov 14, 2026/)
    expect(approvalStateLine(approvalOf({ state: 'denied' }), now)).toMatch(/^by another device · /)
  })

  it('finds the flavor a release builds in the scan of its project', () => {
    expect(flavorOf(projectOf(), releaseOf())?.iosBundleId).toBe('com.acme')
    expect(flavorOf(projectOf(), releaseOf({ app: 'other' }))).toBeUndefined()
    expect(flavorOf(undefined, releaseOf())).toBeUndefined()
    expect(flavorOf(projectOf(), null)).toBeUndefined()
  })

  it('says what approving does, and where a shipped build goes', () => {
    const approval = approvalOf()
    const target = { flavor: 'prod', bundleId: 'com.acme', baseBranch: 'develop' }
    expect(approvalConsequence(approval, target)).toBe(
      'XPath builds 1.2.0 (8) from 0123456 and releases it to the stores. It goes out as prod · com.acme.',
    )
    expect(approvalConsequence({ ...approval, action: 'prod_patch' })).toBe(
      'XPath publishes a Shorebird patch of 1.2.0 (8) built from 0123456.',
    )
    expect(approvalConsequence({ ...approval, action: 'store_submission' }, target)).toContain(
      'submits 1.2.0 (8) for store review. It goes out as',
    )
    expect(approvalConsequence({ ...approval, action: 'push' }, target)).toBe(
      'XPath pushes the release commit 0123456 and the tag of 1.2.0 (8) to GitHub.',
    )
    expect(approvalConsequence({ ...approval, action: 'merge' }, target)).toContain('into develop')
    expect(approvalConsequence({ ...approval, action: 'merge', version: undefined })).toBe(
      'XPath merges the release pull request of 0123456 into the base branch with a merge commit.',
    )
    expect(approvalConsequence({ ...approval, action: 'delete' })).toBe(
      'XPath deletes what the job asks to delete, on 0123456.',
    )
    expect(approvalConsequence({ ...approval, action: 'rollout' })).toBe(
      'The job goes on with its rollout change.',
    )
  })
})
