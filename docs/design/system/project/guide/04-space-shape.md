# Space, shape, density, windows

## Spacing

A 2px sub-grid with 4px steps doing most of the work.

| Path | Value | Use |
|---|---|---|
| `space.2` | 2px | Icon-to-count gap, badge inner padding. |
| `space.4` | 4px | Icon to label in badges and chips. |
| `space.6` | 6px | Icon to label in rows and buttons; stacked label + value. |
| `space.8` | 8px | Gap between controls in a toolbar group, between chips. |
| `space.10` | 10px | Row inline padding (sidebar, lists), node padding. |
| `space.12` | 12px | Table cell padding, card inner gaps. |
| `space.16` | 16px | Panel padding, gap between toolbar groups. |
| `space.20` | 20px | Content-area side padding, pane header inset. |
| `space.24` | 24px | Gap between stacked panels at comfortable size. |
| `space.32` | 32px | Sheet padding, empty-state stacks. |
| `space.40` | 40px | Dialog padding top. |
| `space.48` | 48px | Empty-state and onboarding outer spacing. |

## Radii and borders

| Path | Value | Use |
|---|---|---|
| `radius.xs` | 2px | Checkbox, meter fills, skeleton bars. |
| `radius.sm` | 3px | Badges, chips, agent marker, keycaps. |
| `radius.md` | 4px | Buttons, fields, rows, panels, pipeline nodes. |
| `radius.lg` | 8px | Popovers, menus, sheets, dialogs, toasts, command palette. |
| `radius.full` | 999px | Toggles, slot dots, progress tracks. |
| `border.width.hairline` | 1px | Every panel and divider. |
| `border.width.emphasis` | 1.5px | Pipeline wires; dashed for not-yet-reached edges. |
| `border.width.focus` | 2px | Focus ring width. |
| `border.focus-offset` | 2px | Gap between control and focus ring, painted in the surface colour. |
| `border.running` | 1px | Extra inset ring on a running node (2px total, info.default). |

Radii stay at 3–4px on the window; only things that float get `radius.lg`. Rules are hairlines; the pipeline's wires are `border.width.emphasis`, solid once the upstream stage finished, dashed while not yet reached.

## Elevation

| Path | Light | Dark | Use |
|---|---|---|---|
| `elevation.0` | `none` | `none` | Everything on the window: panels are flat with hairlines. No cards inside cards. |
| `elevation.1` | `0 1px 2px rgba(27, 27, 24, 0.06)` | `none` | Light only: the selected segmented item and toolbar buttons pressed. Dark: surface.selected tint. |
| `elevation.2` | `0 2px 6px rgba(27, 27, 24, 0.08), 0 8px 24px rgba(27, 27, 24, 0.10)` | `none` | Popovers, menus, toasts, tooltips. Dark: surface.overlay tint + border.default. |
| `elevation.3` | `0 4px 12px rgba(27, 27, 24, 0.10), 0 24px 48px rgba(27, 27, 24, 0.16)` | `none` | Sheets, dialogs, command palette. Dark: surface.overlay + border.strong at 1px + scrim behind. |

## Density

The default row is **32px** (`size.row.default`). A **compact density exists**: View ▸ Compact Rows (⌃⌘=) sets tables, lists, runner lists and log step groups to **26px** (`size.row.compact`). The sidebar (28px section rows, 40px two-line project rows), toolbar and controls do not change. Flutter: `XpSizes.compact`.

| Path | Value | Use |
|---|---|---|
| `size.row.default` | 32px | Default list and table row height (sidebar project rows 40px: two lines). |
| `size.row.compact` | 26px | Compact density (View ▸ Compact Rows, ⌃⌘=). Tables, log groups, runner lists; never the sidebar. |
| `size.row.sidebar` | 28px | Sidebar section rows. |
| `size.control.sm` | 24px | Inline buttons in rows, keycaps rows, chips. |
| `size.control.md` | 28px | Default buttons, fields, segmented controls, search. |
| `size.control.lg` | 32px | Sheet and dialog footer buttons, the approval hero buttons. |
| `size.node.height` | 34px | Pipeline job node. |
| `size.toolbar.height` | 52px | Window title area + toolbar (traffic lights live in it). |
| `size.sidebar.width` | 232px | Sidebar default width; resizable 200–320px. |
| `size.console.height` | 268px | Console default height; min 160px; collapsed strip 34px. |
| `size.icon.xs` | 12px | Icons inside type.code and type.label runs. |
| `size.icon.sm` | 14px | Status icons in badges, rows, nodes. |
| `size.icon.md` | 16px | Sidebar, toolbar, buttons. |
| `size.icon.lg` | 20px | Hero status, sheet headers. |
| `size.icon.xl` | 32px | Empty and error states. |

## Window sizes and how panes collapse

| Path | Value | Use |
|---|---|---|
| `window.min.width` | 1100px | Minimum window width. Sidebar 200px, console collapsed to its strip by default, ledger drops Patches column into the row menu. |
| `window.min.height` | 700px | Minimum window height. Console max 40% of height. |
| `window.comfortable.width` | 1440px | Design reference width. Sidebar 232px, horizontal pipeline, console 268px. |
| `window.comfortable.height` | 900px | Design reference height. |
| `window.large.width` | 1728px | Large (16-inch MBP default). Content grows; a job view adds the step list beside the log. |
| `window.large.height` | 1117px | Large height. Console 320px. |
| `window.breakpoint.pipeline-vertical` | 760px | Content width below which the pipeline graph switches to its vertical layout (also the menu bar extra and narrow web). |
| `window.breakpoint.sidebar-collapse` | 1180px | Window width below which the sidebar starts hidden (⌃⌘S to show as overlay). |

- **Large, 1728×1117:** sidebar 232px; content grows; the job view shows its step list (280px) beside the log; console 320px.
- **Comfortable, 1440×900 (reference):** sidebar 232px, horizontal pipeline, ledger with all columns, console docked at 268px.
- **1180–1439 wide:** sidebar narrows towards 200px; ledger moves the Patches column into the row's ⋯ menu; pipeline nodes hide the runner name until hover.
- **Minimum, 1100×700:** sidebar starts hidden (toolbar button or ⌃⌘S shows it as an overlay); console collapses to its 34px strip unless a job is open; console never exceeds 40% of the height.
- **Content narrower than 760px** (split view, menu bar extra, narrow web): the pipeline graph switches to its vertical layout and the ledger becomes one card per flavor.
