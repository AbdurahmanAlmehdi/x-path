# Formatting

## Times

- **Relative** in lists, cards, sidebar and the menu bar extra for anything within 24 hours: `just now` (<1 min), `4m ago`, `2h ago`. Then `Yesterday 14:02`, then `Oct 11, 14:02`, then `Oct 11, 2025` past a year.
- **Absolute** wherever order matters: logs (`14:02:41`), timelines (`Oct 13, 14:09`), approvals' requested time (`14:09`). 24-hour clock, the engine's machine time zone, which is shown in the tooltip: `2026-10-13 14:02:41 GMT+2`.
- **Countdowns** for expiries: `expires in 23h 51m`; under one hour `expires in 42m` and the pair turns `caution`; expired is a status, not `-3m`.
- Every relative time has the absolute one in its tooltip.

## Durations

`41s`, `6m 12s`, `1h 04m` (seconds dropped from an hour up), `0.4s` under one second. Always `type.code`. Live durations tick each second. Tool output quoted in the log keeps its own format (`312.4s`).

## Sizes

Decimal units like Finder: `812 KB`, `38.9 GB`, `312 MB`. One decimal below 100, none from 100 up. A non-breaking space between number and unit. Totals and reclaimable space use the same unit in one sentence: `38.9 GB of 51.2 GB reclaimable`.

## Versions, builds, tags

- In the UI a version is `5.4.1 (3283)`: marketing version, then the build number in parentheses, in `type.code`.
- A git tag is written as the tag: `v5.4.1+3283`. A Shorebird patch is `5.4.1-p2`; a list of patches `p1 · p2`.
- A change is `5.3.7 → 5.4.1`. Never "v" in front of a version except in a tag.

## SHAs

Seven characters (`9a3bc0d`) in `type.code`. Clicking copies the full 40-character SHA; the label swaps to "Copied" for 1.2s. Tooltip shows the full SHA and the commit message.

## Truncation

- **Middle ellipsis** for identifiers whose both ends matter: branch names (`release/5.4.1…forced-update`), bundle IDs (`com.sixdtec.…captain.dev`), file paths, artifact names. Keep the first segment and the last segment whole.
- **Tail ellipsis** for prose: commit messages, release notes, finding messages.
- **Never truncate** versions, build numbers, SHAs, statuses or durations: their column is sized to fit.
- The full value is always in the tooltip and on copy.

## Numbers and words

- Thousands separators: `1,284 passed`. Percentages without space: `20%`. Slots: `2/3`.
- Sentence case everywhere ("Mark approved", "Free up space"); mono caps only for `type.label`.
- An action that opens a sheet ends with an ellipsis: `Dispatch…`, `Review…`, `Deny…`.
- Project and app names verbatim (`mataa_new_app`), in Sans.
