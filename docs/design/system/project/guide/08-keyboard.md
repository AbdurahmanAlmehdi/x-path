# Keyboard

Keyboard-first for the release owner. Shortcuts follow macOS conventions (⌘ for app commands, ⇧⌘ for app-wide panes, ⌃⌘ for window layout); the web dashboard maps ⌘ to Ctrl on non-Mac platforms.

| Shortcut | Command |
|---|---|
| ⌘K | Command palette (go to anything, run any command) |
| ⌘N | Dispatch… |
| ⌘R | Re-run job |
| ⌥⌘R | Resume from selected step |
| ⌘. | Cancel job |
| ⇧⌘A | Approvals (Review… on the needs-you bar) |
| ⌘1 – ⌘9 | Projects in sidebar order |
| ⌘[ / ⌘] | Back / Forward |
| ⌃⌘S | Show / hide sidebar |
| ⇧⌘C | Show / hide console |
| ⌘F | Find in log |
| ⌘G / ⇧⌘G | Next / previous match |
| ⌘E | Jump to error |
| ⌘↓ | Follow tail |
| ⇧⌘T | Toggle timestamps |
| ⌥Z | Toggle wrap |
| ⌃⌘= | Compact rows |
| ⌘C | Copy selection (a selected row copies its identifier: SHA, version, bundle ID) |
| ⌘, | Settings |

## Where hints appear

- **Always:** in menus (system), in tooltips of every toolbar button, and right-aligned in command palette rows.
- **Inline on a button** only for the screen's top actions: `Dispatch…`, `Cancel ⌘.`, `Re-run ⌘R`, `Review… ⇧⌘A`, and in search fields' placeholders (`Filter log ⌘F`). Inline hints are `type.code` in `color.text.tertiary` (on accent/warning fills: the fill's on-colour).
- Keycaps (single glyph boxes) appear only in the palette, the shortcut sheet (⌘/) and onboarding.
- No shortcut is a single letter without a modifier, except inside the log viewer while it has focus (`/` to search, `n` / `N` for matches) and in lists (↑ ↓ ↩ Space).
- Return never approves or submits anything risky: approvals use ⌘↩ after the arming delay.
