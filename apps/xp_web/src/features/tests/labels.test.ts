import { describe, expect, it } from 'vitest'

import { baselineOf, testRunOf } from '@/testing/fixtures'
import { formatTime } from '@/ui/format'

import { comparison, runLabel, testSections, testStats } from './labels'

describe('test labels', () => {
  it('names a run in the picker by app, time and baseline', () => {
    expect(runLabel({ jobId: 'job_1', appPath: '.', createdAt: '2026-11-14T09:00:00Z', baseline: true })).toBe(
      `${formatTime('2026-11-14T09:00:00Z')} · baseline`,
    )
    expect(runLabel({ jobId: 'job_2', appPath: 'apps/admin', branch: 'main', baseline: false })).toBe(
      'apps/admin · just ended',
    )
    expect(runLabel({ jobId: 'job_3', baseline: false })).toBe('')
  })

  it('says what a run is compared with', () => {
    const { run } = testRunOf()
    expect(comparison(run, baselineOf())).toBe(
      `Compared with the baseline of main from ${formatTime('2026-11-13T09:00:00Z')}`,
    )
    expect(comparison(run, undefined)).toBe('Compared with the baseline run of job_1')
    expect(comparison({ ...run, baseline: true }, undefined)).toBe('This run is the baseline of main')
    expect(comparison({ ...run, diff: { ...run.diff, comparedTo: undefined } }, undefined)).toBe(
      'No baseline yet, so every failure counts as new',
    )
  })

  it('counts a run, and shows missing tests only when some are', () => {
    const { run } = testRunOf()
    expect(testStats(run)).toEqual([
      [1, 'new failures'],
      [1, 'in baseline'],
      [1, 'fixed'],
      [7, 'passed'],
      [2, 'failed'],
      [0, 'errored'],
      [1, 'skipped'],
    ])
    const missing = testRunOf({ diff: { ...run.diff, missing: [{ suite: 'test/d_test.dart', name: 'd' }] } })
    expect(testStats(missing.run).at(-1)).toEqual([1, 'missing'])
  })

  it('lists new failures first, then the baseline failures, fixed and missing tests', () => {
    const response = testRunOf({
      diff: {
        comparedTo: 'job_1',
        newFailures: [
          { suite: 'test/a_test.dart', name: 'a breaks' },
          { suite: 'test/e_test.dart', name: 'e is on another page' },
        ],
        fixed: [{ suite: 'test/c_test.dart', name: 'c works' }],
        missing: [{ suite: 'test/d_test.dart', name: 'd' }],
        stillFailing: 3,
      },
    })

    const sections = testSections(response)

    expect(sections.map((section) => [section.title, section.count])).toEqual([
      ['New failures', 2],
      ['Failing in the baseline too', 3],
      ['Fixed since the baseline', 1],
      ['In the baseline, not in this run', 1],
    ])
    expect(sections[0]!.lines).toEqual([
      { ref: { suite: 'test/a_test.dart', name: 'a breaks' }, label: 'Failed', tone: 'negative', message: 'Expected: 1' },
      // Off the page of failing tests read: no status, no message.
      { ref: { suite: 'test/e_test.dart', name: 'e is on another page' }, label: 'Failed', tone: 'negative', message: undefined },
    ])
    // Only the baseline failures on this page are listed, though the engine counts 3.
    expect(sections[1]!.lines.map((line) => [line.ref.name, line.label])).toEqual([['b still breaks', 'Errored']])
    expect(sections[2]!.lines[0]).toMatchObject({ label: 'Fixed', tone: 'positive' })
    expect(sections[3]!.lines[0]).toMatchObject({ label: 'Not reported', tone: 'neutral' })
  })

  it('lists nothing when every test passed and nothing changed', () => {
    const response = testRunOf({
      diff: { comparedTo: 'job_1', newFailures: [], fixed: [], missing: [], stillFailing: 0 },
    })

    expect(testSections({ ...response, tests: [], total: 0 })).toEqual([])
  })
})
