# Icons

**Phosphor**, one family across both surfaces: MIT licensed, shipped in Flutter by `phosphor_flutter` (`PhosphorIconsRegular.*`, `PhosphorIconsFill.*`) and drawn the same on the web. 256-unit grid, 1.5-ish optical stroke at our sizes.

- **Regular (outlined) is the default** for everything: status, sidebar, toolbar, buttons, empty states.
- **Fill only for selection and the hero:** the selected sidebar section's icon, toolbar toggles that are on (Follow, Wrap, Timestamps), and the 20px status icon in a screen's hero. Never fill to add emphasis elsewhere. No Bold, Thin, Light or Duotone weights.
- **Sizes:** `size.icon.xs` 12 (inside code and label runs), `size.icon.sm` 14 (status in badges, rows, nodes), `size.icon.md` 16 (sidebar, toolbar, buttons), `size.icon.lg` 20 (hero, sheet headers), `size.icon.xl` 32 (empty and error states). Icons take the text colour of their label unless they carry a status.
- **Icons never stand alone** except toolbar icon buttons, which have a tooltip with the shortcut and an accessible label.
- **Platform marks** (`apple-logo`, `android-logo`, `app-store-logo`, `google-play-logo`) only in lane headers and platform chips, in the text colour, never in brand colours.
- **Which icons animate:** `circle-notch` (running, building, runner busy) spins; `arrows-clockwise` (reconnecting, runner updating) turns slower. Nothing else moves.
- **Agent:** `robot`, only inside the agent marker.

Core set: `circle-notch`, `check-circle`, `x-circle`, `circle-dashed`, `hourglass-medium`, `hand-palm`, `stop-circle`, `skip-forward-circle`, `pause-circle`, `eye`, `clock`, `radio-button`, `git-merge`, `archive`, `paper-plane-tilt`, `upload-simple`, `users-three`, `check`, `prohibit`, `clock-countdown`, `plugs-connected`, `arrows-clockwise`, `cloud-slash`, `lock-simple`, `warning`, `info`, `seal-check`, `seal-warning`, `key`, `question`, `robot`, `magnifying-glass`, `git-branch`, `tag`, `git-commit`, `copy`, `terminal-window`, `hard-drives`, `laptop`, `tree-structure`, `database`, `push-pin`, `trash`, `package`, `test-tube`, `command`, `sidebar-simple`, `caret-down`, `caret-right`, `x`, `plus`, `dots-three`, `arrow-line-down`, `arrow-u-down-left`, `lightbulb`, `pencil-simple`, `play`, `arrow-clockwise`, `funnel`.
