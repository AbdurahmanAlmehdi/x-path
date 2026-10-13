XPath is a release tool for Flutter teams: Xcode's calm precision, Railway's clarity about what is running where, GitHub Actions' readable pipeline. This system is the **Run Sheet** direction: the release is one readable pipeline across the top, a ledger of versions under it, and a live console docked below like Xcode's debug area. Ink on paper, hairline rules, labels in mono caps, no shadows on the window, no cards inside cards. Colour is spent on state, and loudly only when a human is needed.

It serves one Flutter codebase on two surfaces: the macOS app now and a Flutter web dashboard later. Nothing here depends on a Mac-only effect; the translucent sidebar is optional garnish over the opaque `color.surface.sidebar`.

## Principles

1. **One hero per screen.** Each screen exists for one thing (a release's state, a job's result, a pending approval). That thing is set in `type.hero` and is the only text at that size.
2. **Calm until a human is needed.** Running is blue and quiet. Done is green and quiet. The only loud fill in the product is `color.warning.default` on the needs-you bar and its count badge.
3. **Never colour alone.** Every status has an icon and a label. Agent work carries the agent marker, never a colour.
4. **Identifiers are code.** Versions, builds, SHAs, bundle IDs, tags, durations and sizes are `type.code`: mono, tabular, copyable.
5. **The log is the only place for terminal colour.** ANSI colours live inside `color.log.surface` and nowhere else.

## Token names map one to one

Every token has a dot path. The same path names it in Flutter and in CSS:

| Path | Flutter (ThemeExtension field) | CSS custom property |
|---|---|---|
| `color.surface.raised` | `XpColors.surfaceRaised` | `--xp-color-surface-raised` |
| `color.status.attention.on-container` | `XpColors.statusAttentionOnContainer` | `--xp-color-status-attention-on-container` |
| `type.code` | `XpTypography.code` | `--xp-type-code` (+ class `.xp-type-code`) |
| `space.12` | `XpSpacing.space12` | `--xp-space-12` |
| `radius.md` | `XpRadii.md` | `--xp-radius-md` |
| `motion.duration.base` | `XpMotion.durationBase` | `--xp-motion-duration-base` |
| `size.row.default` | `XpSizes.rowDefault` | `--xp-size-row-default` |

Rule: CSS = `--xp-` + the path with dots as hyphens. Flutter = the family class (`color` → `XpColors`, `type` → `XpTypography`, `space` → `XpSpacing`, `radius` → `XpRadii`, `border` → `XpBorders`, `elevation` → `XpElevation`, `size` → `XpSizes`, `motion` → `XpMotion`, `window` → `XpWindow`) and the camelCase of the rest; when that would start with a digit the family word leads (`space.12` → `space12`). In this system's token list, each token's name is its CSS property without `--`, and its note starts with the path and the Flutter field.

## Consuming it

- **Flutter (macOS now, web later):** `assets/Handoff/xp_tokens.dart` holds every `ThemeExtension` (`XpColors.light` / `.dark`, `XpTypography`, `XpSpacing`, `XpRadii`, `XpBorders`, `XpElevation.light` / `.dark`, `XpSizes.standard` / `.compact`, `XpMotion.standard` / `.reduced`, `XpWindow`) plus `enum XpStatus` (label, pair, Phosphor icon, motion) and `xpTheme(brightness, compact:, reduceMotion:)`. Read with `context.xpColors.surfaceRaised`.
- **CSS / web:** `assets/Handoff/xp-tokens.css` declares every property for light, `[data-theme="dark"]` and `prefers-color-scheme`, and zeroes durations under `prefers-reduced-motion`.
- **Codegen:** `assets/Handoff/xp-tokens.json` is the canonical list: each path with its CSS name, Flutter name, light and dark values, and usage; plus the full status registry and the agent marker.
- **Fonts:** IBM Plex Sans and IBM Plex Mono (OFL). Ship the TTFs as Flutter assets; the web loads them from Google Fonts.
- **Icons:** Phosphor, Regular weight, from `phosphor_flutter` (see Icons).

## Using the colours

- Lay the window on `color.surface.window`; put panels on `color.surface.raised` with a 1px `color.border.default` hairline and `radius.md`. Wells inside panels (fields, code, meter tracks) are `color.surface.sunken`. Menus, popovers, sheets and the palette are `color.surface.overlay`.
- Body text is `color.text.primary`; metadata is `color.text.secondary`; placeholders and shortcut hints are `color.text.tertiary`. All three read 4.5:1 on every surface in both themes.
- `color.accent.default` is for the one primary action, links, focus and selection. It never means a status.
- Statuses use their pair: `color.status.<pair>.container` behind `color.status.<pair>.on-container`. Inline status (icon + label, no container) uses `on-container` straight on the surface.

## Components on this page

Every component card renders **light and dark side by side** from the same markup and shows its states (default, hover, pressed, focused, disabled, loading, error, where they apply; each README says which do not). The cards are a visual reference for the Flutter widgets, not a web widget library: `components/bundle.css` paints them only from the tokens, and `components/bundle.js` only draws the Phosphor icons and the two-pane frame.
