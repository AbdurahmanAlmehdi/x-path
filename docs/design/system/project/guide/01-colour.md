# Colour

## Surfaces and elevation

| Surface | Light | Dark | Use |
|---|---|---|---|
| `color.surface.window` | `#F6F5F1` | `#141412` | Content area behind panels: the paper the run sheet sits on. |
| `color.surface.sidebar` | `#EDECE6` | `#191917` | Sidebar and the collapsed console strip. Flutter may make it translucent on macOS; this is the opaque fallback and the web value. |
| `color.surface.base` | `#FBFAF7` | `#1A1A18` | Toolbar / window title area and pane headers. |
| `color.surface.raised` | `#FFFFFF` | `#1E1E1B` | Panels on the window: pipeline rail, ledger, cards, table bodies. Dark: one tint step up, no shadow. |
| `color.surface.sunken` | `#EFEEE8` | `#121210` | Wells inside a raised panel: text fields, code blocks, meter tracks, skeleton base. |
| `color.surface.overlay` | `#FFFFFF` | `#262623` | Menus, popovers, command palette, sheets, dialogs, toasts. Dark: two tint steps up, no shadow. |
| `color.surface.hover` | `#F1F0EB` | `#262622` | Hover fill for rows, sidebar items and tertiary buttons on base, raised or sidebar. |
| `color.surface.pressed` | `#E6E5DE` | `#2E2D29` | Pressed fill for the same. |
| `color.surface.inverse` | `#1B1B18` | `#ECEAE3` | Inverse fill: selected segment, tooltips, the copied-SHA confirmation. |
| `color.surface.selected` | `#FFFFFF` | `#2A2A25` | Selected sidebar item: sheet plus an inset strong border (see Sidebar). |

Light elevation is hairline first, shadow only for things that float (`elevation.2` popovers, menus, toasts; `elevation.3` sheets, dialogs, palette). **Dark elevation is surface tint, not shadow:** each level is one step lighter (`window` → `raised` → `overlay`), floating things add a 1px `color.border.default` (popovers) or `color.border.strong` (sheets, dialogs) and the scrim. Dark shadow tokens are `none`.

## How many colourful things a screen may have

- **One hero** (`type.hero`), and it may carry its status colour.
- **One accent-filled button** (`color.accent.default`), the screen's primary action. Everything else is secondary or tertiary.
- **At most one warning fill** (`color.warning.default`): the needs-you bar's Review… button and the needs-you count badge in the sidebar. When the needs-you bar is showing, it is the screen's loudest element; nothing else uses a filled container.
- Status pairs as many times as the data needs, but containers only on badges, the hero and the needs-you bar; table rows use inline status (icon + label).
- Zero decorative colour: no tinted panels, no coloured section headers, no gradients.

## Colour in the log versus the chrome

- ANSI colours (`color.log.ansi.*`) appear only as text runs inside `color.log.surface`. The chrome never borrows them, and the log never borrows status containers.
- Inside the log the chrome-like parts (step group headers, the sticky header, the search bar) are chrome: they use status icons and text tokens, not ANSI.
- Row tints are limited to `color.log.stderr-row`, `color.log.error-row`, `color.log.current-row` (the streaming tail while following), `color.log.match` and `color.log.match-active`.
- Bold (SGR 1) is weight 600, never a brighter colour. Dim (SGR 2) on default text is `color.log.dim`; dim on a coloured run keeps the colour (dimming it would drop below 4.5:1).
- Background ANSI colours (SGR 40–47, 100–107) render as the matching `color.log.ansi.*` at 16% over `color.log.surface` with the foreground left as is, so text never loses contrast.

## Focus, selection, scrim

- Focus: 2px solid `color.focus.ring` with a 2px gap in the surface colour (`border.width.focus`, `border.focus-offset`), following the control's radius. 3:1 on every surface in both themes.
- Selected rows and text: `color.selection.default`; text keeps `color.text.primary`.
- `color.scrim.default` behind sheets and dialogs only. Popovers and menus have no scrim.

## Agent marker

Anything started or requested by an AI agent carries the agent marker: a 1px **dashed** `color.agent.ink` border, `radius.sm`, the Phosphor `robot` icon, `AGENT` in `type.label` and the agent's name in `type.body-strong` ("AGENT · Claude Code (xp mcp)"). It has no colour of its own, so it never competes with status, and it sits beside the status, never instead of it. In dense tables it shrinks to the icon + name with `color.agent.container` behind. People get no marker; schedules get the `clock` icon and "Schedule".
