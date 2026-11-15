/** A link of the shell's sidebar. */
export interface NavItem {
  label: string
  to: string
  /** Whether it shows how many approvals wait ("needs you"). */
  needsYou?: boolean
}

/** A titled group of links. */
export interface NavSection {
  label: string
  items: NavItem[]
}

/**
 * The shell's sidebar, in the order of the Mac app's, plus the people and
 * tokens of the engine, which only the dashboard manages.
 */
export const navigation: NavSection[] = [
  {
    label: 'Work',
    items: [
      { label: 'Projects', to: '/projects' },
      { label: 'Runs', to: '/runs' },
      { label: 'Approvals', to: '/approvals', needsYou: true },
    ],
  },
  {
    label: 'Engine',
    items: [
      { label: 'Runners', to: '/runners' },
      { label: 'Storage', to: '/storage' },
      { label: 'Credentials', to: '/credentials' },
      { label: 'People', to: '/people' },
      { label: 'Tokens', to: '/tokens' },
      { label: 'Settings', to: '/settings' },
    ],
  },
]
