import type { TestBaseline, TestRef, TestRun, TestRunResponse } from '@/api/client'
import { formatTime } from '@/ui/format'

import type { KnownTestRun } from './stores/tests'

/** A test in a section of the run shown. */
export interface TestLine {
  ref: TestRef
  label: string
  tone: 'negative' | 'positive' | 'neutral'
  message?: string
}

/** A section of the run shown: its title, how many tests the engine counts in it, and those listed. */
export interface TestSection {
  title: string
  count: number
  lines: TestLine[]
}

/** What a run is called in the picker: app, when, baseline. */
export function runLabel(known: KnownTestRun): string {
  return [
    known.appPath && known.appPath !== '.' ? known.appPath : undefined,
    known.createdAt ? formatTime(known.createdAt) : known.branch ? 'just ended' : undefined,
    known.baseline ? 'baseline' : undefined,
  ]
    .filter(Boolean)
    .join(' · ')
}

/** What [run] is compared with: itself as the baseline, [baseline] when known, else no baseline yet. */
export function comparison(run: TestRun, baseline: TestBaseline | undefined): string {
  if (run.baseline) return `This run is the baseline of ${run.branch}`
  if (!run.diff.comparedTo) return 'No baseline yet, so every failure counts as new'
  return baseline
    ? `Compared with the baseline of ${baseline.branch} from ${formatTime(baseline.createdAt)}`
    : `Compared with the baseline run of ${run.diff.comparedTo}`
}

/** The counts of [run], as `[value, label]`; `missing` only when tests went missing. */
export function testStats(run: TestRun): Array<readonly [number, string]> {
  const { counts, diff } = run
  return [
    [diff.newFailures.length, 'new failures'],
    [diff.stillFailing, 'in baseline'],
    [diff.fixed.length, 'fixed'],
    [counts.passed, 'passed'],
    [counts.failed, 'failed'],
    [counts.errored, 'errored'],
    [counts.skipped, 'skipped'],
    ...(diff.missing.length > 0 ? [[diff.missing.length, 'missing'] as const] : []),
  ]
}

const sameTest = (a: TestRef) => (b: TestRef) => a.suite === b.suite && a.name === b.name

/**
 * The tests of [response] that changed or still fail, new failures first;
 * sections with nothing to list are left out. The failing tests come one
 * page at a time (`tests`, of `total`): a failure off this page shows as
 * Failed, without its message, and the baseline's failures listed are
 * the ones on this page.
 */
export function testSections(response: TestRunResponse): TestSection[] {
  const { diff } = response.run
  const failure = (ref: TestRef): TestLine => {
    const test = response.tests.find(sameTest(ref))
    return {
      ref,
      label: test?.status === 'errored' ? 'Errored' : 'Failed',
      tone: 'negative',
      message: test?.message,
    }
  }
  const still = response.tests.filter((test) => !diff.newFailures.some(sameTest(test)))
  const sections: TestSection[] = [
    { title: 'New failures', count: diff.newFailures.length, lines: diff.newFailures.map(failure) },
    { title: 'Failing in the baseline too', count: diff.stillFailing, lines: still.map(failure) },
    {
      title: 'Fixed since the baseline',
      count: diff.fixed.length,
      lines: diff.fixed.map((ref): TestLine => ({ ref, label: 'Fixed', tone: 'positive' })),
    },
    {
      title: 'In the baseline, not in this run',
      count: diff.missing.length,
      lines: diff.missing.map((ref): TestLine => ({ ref, label: 'Not reported', tone: 'neutral' })),
    },
  ]
  return sections.filter((section) => section.lines.length > 0)
}
