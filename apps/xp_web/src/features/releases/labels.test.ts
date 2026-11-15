import { describe, expect, it } from 'vitest'

import type { StoreStatus } from '@/api/client'
import { approvalOf, releaseOf } from '@/testing/fixtures'

import {
  isOver,
  laneSteps,
  liveBefore,
  mergeCaption,
  minVersionText,
  releaseHero,
  releasePatches,
  releaseStatus,
  releaseTimeline,
  statusSource,
  storeName,
  storeStatus,
  storesApproved,
  variableList,
} from './labels'

describe('release labels', () => {
  const reads = () => true
  const marks = () => false

  it('names states, stores and sources as the Mac app does', () => {
    expect(releaseStatus('in_review')).toEqual({ label: 'In review', tone: 'info' })
    expect(releaseStatus('merged').tone).toBe('merged')
    expect(isOver('merged')).toBe(true)
    expect(isOver('live')).toBe(false)
    expect(storesApproved('live')).toBe(true)
    expect(storesApproved('in_review')).toBe(false)
    expect(storeName('apple')).toBe('App Store')
    expect(variableList(['apple', 'play'])).toBe('min_version_ios and min_version_android')
    const apple = (['pending', 'uploaded', 'in_review', 'rejected', 'approved', 'live'] as const).map(
      (state) => storeStatus('apple', state).label,
    )
    expect(apple).toEqual(['Not uploaded', 'Uploaded', 'In review', 'Rejected', 'Pending developer release', 'Ready for sale'])
    expect(storeStatus('play', 'rejected').label).toBe('Not approved')
    expect(storeStatus('play', 'approved').label).toBe('Approved · not published')
    expect(storeStatus('play', 'live').label).toBe('Published')
    expect((['upload', 'api', 'lookup', 'manual'] as const).map((source) => statusSource('apple', source))).toEqual([
      'Upload step',
      'App Store Connect API',
      'iTunes lookup',
      'Marked by hand',
    ])
    expect(statusSource('play', 'api')).toBe('Google Play API')
  })

  it('says in the hero which store rejected it or has it live', () => {
    const rejected = (stores: StoreStatus[]) => releaseHero(releaseOf({ state: 'rejected', stores }))
    expect(rejected([{ store: 'apple', state: 'rejected', source: 'api' }])).toBe('Rejected by App Store')
    expect(
      rejected([
        { store: 'apple', state: 'rejected', source: 'api' },
        { store: 'play', state: 'rejected', source: 'api' },
      ]),
    ).toBe('Rejected by both stores')
    expect(releaseHero(releaseOf())).toBe('Live on both stores')
    expect(releaseHero(releaseOf({ stores: [{ store: 'play', state: 'live', source: 'api' }] }))).toBe(
      'Live on Google Play',
    )
    expect(releaseHero(releaseOf({ state: 'building' }))).toBe('Building')
  })

  it('says why Merge is not open, or what it merges', () => {
    expect(mergeCaption(releaseOf({ state: 'merged', mergeCommit: 'fedcba9876543' }), [], reads)).toBe('Merged · fedcba9')
    expect(mergeCaption(releaseOf({ state: 'merged' }), [], reads)).toBe('Merged · ')
    expect(mergeCaption(releaseOf({ state: 'abandoned' }), [], reads)).toBe('The release was abandoned')
    expect(mergeCaption(releaseOf({ mergeEnabled: true }), [], reads)).toBe('release/1.1.0 → main · both stores live')
    expect(mergeCaption(releaseOf({ mergeEnabled: true, branch: undefined }), [], reads)).toBe('Both stores live')
    const merging = releaseOf({ mergeRunId: 'run_7' })
    expect(mergeCaption(merging, [approvalOf({ runId: 'run_7' })], reads)).toBe(
      'Merge requested · waits for your approval',
    )
    expect(mergeCaption(merging, [approvalOf({ runId: 'run_7', state: 'approved' })], reads)).toBe('Merge requested')
    expect(
      mergeCaption(
        releaseOf({ state: 'rejected', stores: [{ store: 'play', state: 'rejected', source: 'api' }] }),
        [],
        reads,
      ),
    ).toBe('Google Play rejected this build')
    expect(mergeCaption(releaseOf(), [], reads)).toBe('The release has no pull request yet')
    expect(mergeCaption(releaseOf({ prNumber: 12 }), [], reads)).toBe('Both stores live')
    const reviewing = releaseOf({
      state: 'in_review',
      stores: [
        { store: 'apple', state: 'in_review', source: 'api' },
        { store: 'play', state: 'in_review', source: 'api' },
      ],
    })
    expect(mergeCaption(reviewing, [], reads)).toBe('Waits for both stores to go live')
    expect(mergeCaption({ ...reviewing, stores: reviewing.stores.slice(1) }, [], reads)).toBe(
      'Waits for Google Play to go live',
    )
    expect(mergeCaption(reviewing, [], (store) => store === 'play')).toBe(
      'Mark App Store live and Google Play must go live',
    )
  })

  it('draws the steps of a lane the engine reads', () => {
    const status: StoreStatus = { store: 'apple', state: 'in_review', source: 'api', changedAt: '2026-11-13T09:00:00Z' }
    const steps = laneSteps(status, false)
    expect(steps.map((step) => [step.label, step.phase])).toEqual([
      ['Uploaded', 'done'],
      ['In review', 'now'],
      ['Approved', 'todo'],
      ['Ready for sale', 'todo'],
    ])
    expect(steps[1]?.time).toMatch(/^since Nov 13, 2026/)
    expect(laneSteps({ ...status, detail: 'WAITING_FOR_REVIEW' }, false)[1]?.label).toBe('Waiting for review')
    expect(laneSteps({ ...status, state: 'live' }, false)[3]?.time).toMatch(/^Nov 13, 2026/)
    expect(laneSteps({ ...status, state: 'pending', changedAt: undefined }, false).every((step) => step.phase === 'todo')).toBe(true)
    expect(laneSteps({ ...status, state: 'rejected' }, false).map((step) => step.phase)).toEqual(['done', 'done', 'now'])
  })

  it('draws the steps of a lane marked by hand', () => {
    const status: StoreStatus = { store: 'play', state: 'uploaded', source: 'upload' }
    expect(laneSteps(status, true).map((step) => [step.label, step.phase, step.time])).toEqual([
      ['Uploaded', 'done', undefined],
      ['Unknown', 'now', 'no service account'],
      ['Published', 'todo', undefined],
    ])
    expect(laneSteps({ ...status, store: 'apple' }, true)[1]?.time).toBe('no API key')
    const approved = laneSteps({ ...status, store: 'apple', state: 'approved', changedAt: '2026-11-13T09:00:00Z' }, true)
    expect(approved[1]).toMatchObject({ label: 'Approved', phase: 'now' })
    expect(approved[1]?.time).toMatch(/^since /)
    expect(laneSteps({ ...status, state: 'live' }, true)[2]?.phase).toBe('now')
    expect(laneSteps({ ...status, state: 'pending' }, true)[0]?.phase).toBe('todo')
  })

  it('finds the release a lane replaces', () => {
    const shown = releaseOf({ id: 'rel_2', version: '1.2.0' })
    const before = releaseOf()
    const other = releaseOf({ id: 'rel_0', flavor: 'dev' })
    expect(liveBefore([shown, other, before], shown, 'apple')?.id).toBe('rel_1')
    expect(liveBefore([shown], shown, 'apple')).toBeUndefined()
  })

  it('tells the timeline from the history and the approvals of its runs, newest first', () => {
    const release = releaseOf({ mergeRunId: 'run_8' })
    const approvals = [
      approvalOf({ runId: 'run_1', createdAt: '2026-11-10T09:10:00Z', state: 'approved', decidedAt: '2026-11-10T09:20:00Z', decidedBy: { tokenId: 't', name: 'Browser', kind: 'web', personName: 'Sam' } }),
      approvalOf({ id: 'apr_2', runId: 'run_8', createdAt: '2026-11-13T09:00:00Z', action: 'merge' }),
      approvalOf({ id: 'apr_3', runId: 'run_9', createdAt: '2026-11-13T09:00:00Z' }),
      approvalOf({ id: 'apr_4', runId: 'run_5', state: 'expired', reason: 'Nobody decided.' }),
    ]
    const history = [
      { kind: 'created' as const, at: '2026-11-10T09:00:00Z' },
      { kind: 'build' as const, at: '2026-11-10T09:05:00Z', detail: '6', runId: 'run_1' },
      { kind: 'store' as const, at: '2026-11-11T09:00:00Z', store: 'apple' as const, detail: 'live', by: 'Mac mini' },
      { kind: 'store' as const, at: '2026-11-11T09:01:00Z', store: 'play' as const, detail: 'later_state' },
      { kind: 'store' as const, at: '2026-11-11T09:02:00Z', detail: 'unknown store' },
      { kind: 'merge_requested' as const, at: '2026-11-12T09:00:00Z' },
      { kind: 'merged' as const, at: '2026-11-12T10:00:00Z', detail: 'fedcba9876543' },
      { kind: 'merged' as const, at: '2026-11-12T10:00:01Z' },
      { kind: 'abandoned' as const, at: '2026-11-12T11:00:00Z', detail: 'Gave up.' },
      { kind: 'rollout_requested' as const, at: '2026-11-12T12:00:00Z' },
      { kind: 'rollout' as const, at: '2026-11-12T13:00:00Z', store: 'play' as const, detail: '20 %' },
      { kind: 'rollout' as const, at: '2026-11-12T13:00:01Z' },
      { kind: 'patch' as const, at: '2026-11-12T14:00:00Z', patchNumber: 1, runId: 'run_5' },
      { kind: 'patch_requested' as const, at: '2026-11-12T15:00:00Z', patchNumber: 1, detail: 'rollback' },
      { kind: 'patch_requested' as const, at: '2026-11-12T15:00:01Z', patchNumber: 1, detail: 'promote' },
      { kind: 'patch_promoted' as const, at: '2026-11-12T16:00:00Z', patchNumber: 1 },
      { kind: 'patch_rolled_back' as const, at: '2026-11-12T17:00:00Z' },
      { kind: 'texts' as const, at: '2026-11-12T18:00:00Z' },
    ]
    const entries = releaseTimeline(release, approvals, history)
    const titles = entries.map((entry) => entry.title)
    // An expired approval ends when it expires, the newest here.
    expect(titles.slice(0, 4)).toEqual([
      'Release 1.2.0 (8) to the stores: expired',
      'Approval requested: Release 1.2.0 (8) to the stores',
      'Approval requested: Merge the release PR of 1.2.0 (8)',
      'Store texts changed',
    ])
    expect(titles).toContain('Approval requested: Merge the release PR of 1.2.0 (8)')
    expect(titles.filter((title) => title.startsWith('Approval requested: Release'))).toHaveLength(2)
    expect(titles).toContain('Release 1.2.0 (8) to the stores: approved')
    expect(titles).toContain('Release 1.2.0 (8) to the stores: expired')
    expect(titles).toContain('App Store: ready for sale')
    expect(titles).toContain('Google Play: later_state')
    expect(titles).toContain('unknown store')
    expect(titles).toContain('Google Play rollout changed')
    expect(titles).toContain('Rollout changed')
    expect(titles).toContain('Rollback of patch 1 requested')
    expect(titles).toContain('Promotion of patch 1 requested')
    expect(titles).toContain('Patch 0 rolled back')
    expect(titles.at(-1)).toBe('Release dispatched')
    expect(entries.find((entry) => entry.title === 'App Store: ready for sale')?.detail).toBe('Mac mini')
    expect(entries.filter((entry) => entry.title === 'Merged into main').map((entry) => entry.detail)).toEqual([
      undefined,
      'fedcba9',
    ])
    expect(entries.find((entry) => entry.title.endsWith(': approved'))?.detail).toBe('Sam')
    expect(entries.find((entry) => entry.title.endsWith(': expired'))?.detail).toBe('Nobody decided.')
    expect(entries.find((entry) => entry.title === 'Abandoned')?.detail).toBe('Gave up.')
  })

  it('tells the timeline of a release from before the history from the release itself', () => {
    const merged = releaseTimeline(
      releaseOf({
        state: 'merged',
        mergeCommit: 'fedcba9876543',
        baseBranch: undefined,
        stores: [
          { store: 'apple', state: 'live', source: 'manual', changedAt: '2026-11-12T09:00:00Z' },
          { store: 'play', state: 'uploaded', source: 'upload' },
        ],
      }),
      [],
    )
    expect(merged.map((entry) => entry.title)).toEqual([
      'Merged into the base branch',
      'App Store: ready for sale',
      'Build 6 started',
      'Release dispatched',
    ])
    expect(merged[1]?.detail).toBe('Marked by hand')
    expect(releaseTimeline(releaseOf({ state: 'merged' }), [])[0]?.detail).toBeUndefined()
    const abandoned = releaseTimeline(releaseOf({ state: 'abandoned', message: 'Gave up.', stores: [] }), [])
    expect(abandoned[0]).toMatchObject({ title: 'Abandoned', detail: 'Gave up.' })
  })

  it('knows where each Shorebird patch is', () => {
    expect(
      releasePatches([
        { kind: 'patch', at: '2026-11-12T14:00:00Z', patchNumber: 2 },
        { kind: 'patch', at: '2026-11-12T14:00:00Z', patchNumber: 1 },
        { kind: 'patch_promoted', at: '2026-11-12T15:00:00Z', patchNumber: 1 },
        { kind: 'patch', at: '2026-11-12T15:30:00Z', patchNumber: 1 },
        { kind: 'patch_rolled_back', at: '2026-11-12T16:00:00Z', patchNumber: 2 },
        { kind: 'patch_requested', at: '2026-11-12T16:00:00Z', patchNumber: 3 },
        { kind: 'texts', at: '2026-11-12T16:00:00Z' },
      ]),
    ).toEqual([
      { number: 1, state: 'promoted' },
      { number: 2, state: 'rolledBack' },
    ])
  })

  it('reminds when to raise the minimum version', () => {
    expect(minVersionText(releaseOf({ stores: [] }))).toBe('This release goes to no store.')
    expect(
      minVersionText(releaseOf({ stores: [{ store: 'apple', state: 'in_review', source: 'api' }] })),
    ).toBe(
      'If this release is a forced update, raise min_version_ios to 1.1.0 once the stores have it live. Raising it earlier locks out users who have nothing to update to.',
    )
    expect(minVersionText(releaseOf())).toBe(
      'App Store and Google Play live: if this release is a forced update, raise min_version_ios and min_version_android to 1.1.0 in Firebase Remote Config now.',
    )
    expect(
      minVersionText(
        releaseOf({
          stores: [
            { store: 'apple', state: 'live', source: 'api' },
            { store: 'play', state: 'in_review', source: 'api' },
          ],
        }),
      ),
    ).toBe(
      'App Store live: if this release is a forced update, raise min_version_ios to 1.1.0 in Firebase Remote Config now. Raise min_version_android once Google Play is live.',
    )
  })

  it('reads a marks-only store as marks', () => {
    expect(mergeCaption(releaseOf({ stores: [{ store: 'play', state: 'uploaded', source: 'upload' }] }), [], marks)).toBe(
      'Mark Google Play live',
    )
  })
})
