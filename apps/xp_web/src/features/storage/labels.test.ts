import { describe, expect, it } from 'vitest'

import { buildsLabel, categoryName, categoryRule } from './labels'

describe('storage labels', () => {
  const retention = { keepPerFlavor: 5, logDays: 90 }

  it('names each category as the Mac app does', () => {
    expect((['artifacts', 'logs', 'worktrees', 'mirrors', 'flutter'] as const).map(categoryName)).toEqual([
      'Artifacts',
      'Logs',
      'Worktrees',
      'Mirrors',
      'Flutter SDKs',
    ])
  })

  it('says what retention gives back in each category, with its settings', () => {
    expect(
      (['artifacts', 'logs', 'worktrees', 'mirrors', 'flutter'] as const).map((category) =>
        categoryRule(category, retention),
      ),
    ).toEqual([
      'Builds past the newest 5 of each flavor',
      'Logs of jobs older than 90 days',
      'Worktrees of finished jobs',
      'Mirrors of repositories that are no longer projects',
      "SDKs in XPath's cache that no project pins",
    ])
    expect(categoryRule('logs', { keepPerFlavor: 2, logDays: 7 })).toBe('Logs of jobs older than 7 days')
  })

  it('counts the builds and files of a flavor', () => {
    expect(buildsLabel(1, 3)).toBe('1 build · 3 files')
    expect(buildsLabel(4, 12)).toBe('4 builds · 12 files')
  })
})
