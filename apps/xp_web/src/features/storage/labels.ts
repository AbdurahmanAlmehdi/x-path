import type { RetentionSettings, StorageCategory } from '@/api/client'

const names: Record<StorageCategory, string> = {
  artifacts: 'Artifacts',
  logs: 'Logs',
  worktrees: 'Worktrees',
  mirrors: 'Mirrors',
  flutter: 'Flutter SDKs',
}

/** What the Mac app calls a category of storage. */
export function categoryName(category: StorageCategory): string {
  return names[category]
}

/** What retention gives back in [category], under [retention]. */
export function categoryRule(category: StorageCategory, retention: RetentionSettings): string {
  switch (category) {
    case 'artifacts':
      return `Builds past the newest ${retention.keepPerFlavor} of each flavor`
    case 'logs':
      return `Logs of jobs older than ${retention.logDays} days`
    case 'worktrees':
      return 'Worktrees of finished jobs'
    case 'mirrors':
      return 'Mirrors of repositories that are no longer projects'
    case 'flutter':
      return "SDKs in XPath's cache that no project pins"
  }
}

/** The builds and files of a flavor: `3 builds · 7 files`. */
export function buildsLabel(builds: number, artifacts: number): string {
  return `${builds === 1 ? '1 build' : `${builds} builds`} · ${artifacts} files`
}
