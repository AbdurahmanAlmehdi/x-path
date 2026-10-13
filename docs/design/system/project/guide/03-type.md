# Type

IBM Plex Sans for UI, IBM Plex Mono for everything a machine wrote or a human copies. Both are OFL and ship as Flutter assets; the web loads them from Google Fonts.

| Role | Path | Face | Size / line | Weight | Use |
|---|---|---|---|---|---|
| hero | `type.hero` | Plex Sans | 28/34 | 600 | The one big thing a screen is for: a release's state, a job's result, a pending approval's action. One per screen. Versions inside it switch to type.hero-code. |
| hero-code | `type.hero-code` | Plex Mono | 26/34 | 600 | Version or build inside a hero line. Tabular figures. |
| display | `type.display` | Plex Sans | 34/40 | 700 | Onboarding and empty-state headlines only. |
| headline | `type.headline` | Plex Sans | 20/26 | 600 | Screen titles inside the content area (app header, sheet title). |
| title | `type.title` | Plex Sans | 15/20 | 600 | Panel titles, toolbar title, card titles. |
| title-sm | `type.title-sm` | Plex Sans | 13/18 | 600 | Row titles, sidebar selected project, flavor names. |
| body | `type.body` | Plex Sans | 13/20 | 400 | Default UI text. |
| body-strong | `type.body-strong` | Plex Sans | 13/20 | 500 | Emphasis inside body and button labels. |
| caption | `type.caption` | Plex Sans | 12/16 | 400 | Metadata under a row title, helper text, timestamps in prose. |
| label | `type.label` | Plex Mono | 11/14 | 500 | Section and column labels, set in mono caps. Never for sentences. |
| code | `type.code` | Plex Mono | 12/16 | 500 | Versions, build numbers, SHAs, bundle IDs, tags, durations, sizes. Tabular figures, copyable. |
| code-lg | `type.code-lg` | Plex Mono | 15/20 | 500 | Versions in the ledger's cells and card headers. |
| mono | `type.mono` | Plex Mono | 12.5/21 | 400 | Log lines. ANSI bold = weight 600; dim = log.dim colour. |

- `hero`: one per screen. A release screen: "Waiting for review" with `5.4.1 (3283)` in `type.hero-code` beside it; a job: "Failed at Upload to App Store"; an approval: "Submit 5.4.1 (3283) to App Store".
- `code`: `5.4.1 (3283)`, `9a3bc0d`, `com.sixdtec.mata`, `v5.4.1+3283`, `6m 12s`, `38.9 GB`. Always tabular figures (Flutter: `FontFeature.tabularFigures()`; CSS: `font-variant-numeric: tabular-nums`). Never bold for emphasis; use `code-lg` for size.
- `label`: mono caps, 0.06em tracking, `color.text.secondary`. Column heads and section labels only, never sentences or buttons.
- `mono`: logs at 12.5/21. ANSI bold = 600. Line numbers and timestamps in `color.log.dim`.
- Longer strings: no fixed-width labels; buttons and badges grow; tables truncate cells per Formatting.

## ANSI colour mapping

Mapped for `color.log.surface` (`#FCFBF8` light, `#10100E` dark). Black is remapped in dark and white in light so all sixteen stay above 4.5:1; full row-tint ratios are in Contrast.

| ANSI | SGR | Light | ratio on log | Dark | ratio on log |
|---|---|---|---|---|---|
| `black` | 30 | `#1B1B18` | 16.68 | `#8F8C83` | 5.67 |
| `red` | 31 | `#B42318` | 6.35 | `#F97066` | 6.84 |
| `green` | 32 | `#1B6E44` | 6.04 | `#4CC38A` | 8.60 |
| `yellow` | 33 | `#8A5300` | 6.12 | `#F5C873` | 12.15 |
| `blue` | 34 | `#2449B8` | 7.46 | `#7EA2FF` | 7.71 |
| `magenta` | 35 | `#8E2A86` | 7.18 | `#E08BE0` | 8.11 |
| `cyan` | 36 | `#0B6874` | 6.25 | `#5CC8D6` | 9.69 |
| `white` | 37 | `#5C5B54` | 6.59 | `#DAD7CE` | 13.24 |
| `bright-black` | 90 | `#66645D` | 5.72 | `#A8A59B` | 7.73 |
| `bright-red` | 91 | `#C2300F` | 5.45 | `#FF968E` | 9.08 |
| `bright-green` | 92 | `#227A4E` | 5.12 | `#78DAA9` | 11.25 |
| `bright-yellow` | 93 | `#9A5B00` | 5.24 | `#FFDC8F` | 14.41 |
| `bright-blue` | 94 | `#2D5BD6` | 5.67 | `#A6C0FF` | 10.53 |
| `bright-magenta` | 95 | `#A2349A` | 5.81 | `#F2B2F2` | 11.27 |
| `bright-cyan` | 96 | `#0D7684` | 5.15 | `#8FE1EB` | 12.82 |
| `bright-white` | 97 | `#3B3A35` | 11.01 | `#FFFFFF` | 19.05 |

Default foreground is `color.log.text`; default background is `color.log.surface`. Bold: weight 600. Dim: `color.log.dim` on default text, unchanged on coloured text. Italic and underline are honoured; blink is ignored; inverse swaps to `color.log.text` on `color.log.match`.
