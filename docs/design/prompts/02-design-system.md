Going with the [DIRECTION NAME] direction for XPath from the [link to the visual directions canvas]. Build the design system as a reference page, with light and dark versions side by side. PRODUCT.md is attached again; it stays the source of truth.

It serves one codebase that will reach two surfaces: the Flutter macOS app now and, later, a Flutter web dashboard. Name every token so it maps one to one onto a Flutter `ThemeExtension` and a CSS custom property (e.g. `color.surface.raised` → `XpColors.surfaceRaised` → `--xp-color-surface-raised`). Ship the tokens as a `tokens.json` too.

## Tokens

- **Colour** (semantic names, never raw hues in components): surface (window, sidebar, base, raised, sunken, overlay), text (primary, secondary, tertiary, on-accent, disabled), border (subtle, default, strong), accent (and on-accent), positive, negative, warning, info, focus ring, selection, scrim.
- **Status tokens** for every status in PRODUCT.md §5: one colour pair (container and on-container) plus an icon and a label each. Statuses that mean the same thing to the user can share a pair; say which. Cover: job and step, release, App Store lane, Play lane, Firebase, approval, runner, engine connection, scan finding severity, credential state. Include the animated "running" treatment and its Reduce Motion fallback.
- **Agent marker**: how anything started or requested by an AI agent is marked (colour, icon, label), distinct from status.
- **Type scale** with roles: display, headline, title, body, label, caption, plus:
  - `mono`: logs, with ANSI colour mapping for both themes (the 16 ANSI colours plus bold and dim, checked for contrast on the log background);
  - `code`: versions, build numbers, SHAs, bundle IDs, tags (`5.4.1 (3283)`, `9a3bc0d`, `com.sixdtec.mata`, `v5.4.1+3283`), tabular figures;
  - `hero`: the one big thing a screen is for (a release's state, a job's result, a pending approval).
- **Spacing, radii, borders, elevation** (light and dark; in dark, elevation is surface tint, not shadow). Density: say what the default row height is and whether a compact density exists.
- **Motion**: durations, easings, and where motion is used (sidebar selection, sheet, toast, status change, log streaming, pipeline progress). Every motion has a Reduce Motion fallback.
- **Window sizes**: minimum 1100×700, comfortable 1440×900, large 1728×1117; how panes collapse.

## Components

Show each with all its states (default, hover, pressed, focused, disabled, loading, error) in light and dark:

- sidebar (projects, sections, engine switcher, badges for running and waiting), toolbar, window title area;
- status badge, status icon, running indicator; agent marker;
- version cell (local / TestFlight / Play testing / live), flavor row, app header;
- pipeline graph: stage, job node (with runner and duration), step row; horizontal and vertical layouts;
- log viewer: line numbers, timestamps toggle, ANSI colour, collapsible step groups, sticky step header, search with match count, follow-tail, jump to error, copy, wrap toggle, very long lines;
- store lane (App Store and Play): state, timeline, phased rollout %, manual "mark approved" / "mark live" buttons when no API is configured;
- release card (compact and full), release timeline;
- approval card: action, app, version, commit, requester (person or agent), expiry, approve / deny with the safety pattern you choose;
- runner card: OS, capabilities chips, slots meter, current job, heartbeat;
- test summary with baseline diff (new failures, still failing, fixed);
- dispatch form: workflow picker, flavor and platform chips (matrix), ref picker (branch or tag), version bump, preview of runners and approvals needed;
- workflow builder node and the YAML editor pane (syntax colours, error underline with line number);
- credential row (verified, expiring, expired, missing) and secret input;
- storage bar with reclaimable space, artifact row (pinned, reason kept);
- scan review list (error, warning, info with fix);
- command palette (Cmd-K), keyboard shortcut hints, context menu;
- buttons (primary, secondary, tertiary, destructive), segmented control, text field, search field, picker, toggle, checkbox, tooltip;
- sheet, dialog, popover, toast, inline banner (engine reconnecting, engine unreachable with cached data, secrets locked);
- empty state, error state, skeletons for each card;
- menu bar extra (running jobs, pending approvals, quick dispatch).

## Rules to write down

- How many accent things a screen may have (one hero per screen).
- Icon set (one family that Flutter can ship, outlined vs filled rules, sizes) and which statuses animate.
- Formatting: relative vs absolute times, durations (`6m 12s`), sizes (`38.9 GB`), versions and build numbers, SHAs (7 characters, copyable), truncation of long branch names and bundle IDs (middle ellipsis?).
- Keyboard shortcut conventions and where hints appear.
- When colour is allowed in the log area versus the chrome.
- Contrast of every text/background token pair (list the ratios), including ANSI colours on the log background.
