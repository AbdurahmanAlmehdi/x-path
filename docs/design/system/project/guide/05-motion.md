# Motion

Motion explains a change of place or state; it never decorates. Every motion has a Reduce Motion fallback (macOS Reduce Motion → Flutter `MediaQuery.disableAnimationsOf`; web `prefers-reduced-motion`). Under Reduce Motion every duration becomes `motion.duration.instant` except opacity fades, which may stay at ≤120ms.

| Path | Value | Use |
|---|---|---|
| `motion.duration.instant` | `0ms` | Reduce Motion replacement for every non-essential transition. |
| `motion.duration.fast` | `120ms` | Hover and press fills, toggle thumb, checkbox mark. |
| `motion.duration.base` | `180ms` | Sidebar selection, segmented control thumb, status crossfade. |
| `motion.duration.moderate` | `240ms` | Popover, menu, toast enter; sheet exit. |
| `motion.duration.slow` | `320ms` | Sheet enter, pipeline progress fill, pane collapse. |
| `motion.duration.spin` | `1000ms` | One turn of the running arc (linear, infinite). |
| `motion.duration.pulse` | `1600ms` | Reconnecting / updating rotation (slower than running so they read differently). |
| `motion.easing.standard` | `cubic-bezier(0.2, 0, 0, 1)` | Default for moves inside the window. Flutter: Cubic(0.2, 0, 0, 1). |
| `motion.easing.enter` | `cubic-bezier(0.05, 0.7, 0.1, 1)` | Things arriving: sheet, popover, toast. Flutter: Cubic(0.05, 0.7, 0.1, 1). |
| `motion.easing.exit` | `cubic-bezier(0.3, 0, 1, 1)` | Things leaving. Flutter: Cubic(0.3, 0, 1, 1). |
| `motion.easing.linear` | `linear` | Spinners and progress that tracks real time. Flutter: Curves.linear. |

## Where motion is used

| Where | Motion | Reduce Motion |
|---|---|---|
| Hover / press fills | colour, `duration.fast`, `easing.standard` | instant |
| Sidebar selection | selected fill slides to the new row, `duration.base`, `easing.standard` | instant swap |
| Segmented control, toggle | thumb slides, `duration.base` / `duration.fast` | instant |
| Sheet | slides down from under the toolbar 12px + fades, `duration.slow`, `easing.enter`; leaves `duration.moderate`, `easing.exit`; scrim fades | fade only, 120ms |
| Popover, menu, tooltip | fade + scale 0.98 → 1, `duration.moderate`, `easing.enter`; context menus appear instantly like the system's | fade only, 120ms |
| Toast | rises 8px + fades at bottom right, `duration.moderate`, `easing.enter`; stays 4s (6s with an action, until hovered away) | fade only |
| Status change | icon and label crossfade, container colour transitions, `duration.base` | instant swap |
| Running | arc turns, `duration.spin`, linear, infinite | static ¾ arc + centre dot |
| Reconnecting / updating | arrows turn, `duration.pulse`, linear | static icon |
| Log streaming | none: lines append in place; while following, the view stays pinned to the tail by jumping, not scrolling; when not following, a "↓ 42 new lines" pill fades in (`duration.fast`) | same; pill appears without fade |
| Pipeline progress | an edge turns from dashed to solid when its upstream stage finishes, drawn along its length in `duration.slow`; node state crossfades `duration.base`; progress bars ease to the new value `duration.slow` | edges and bars jump |
| Pane collapse (console, sidebar) | size animates `duration.slow`, `easing.standard` | instant |
| Skeletons | static: no shimmer in either mode | static |
