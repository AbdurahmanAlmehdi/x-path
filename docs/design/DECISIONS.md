# Design decisions (owner, 2026-10-13)

The source of truth for the desktop UI (Phases 15–17) and the brand assets (Phases 18b–18c).

## Sources

| What | Where | Live source |
|---|---|---|
| Product brief | `PRODUCT.md` | — |
| Design system ("Run Sheet") | `system/project/` (README, guides, `assets/Handoff/xp_tokens.dart`, `xp-tokens.json`, `xp-tokens.css`, `tokens.json`) | https://claude.ai/artifact/Ro9wMV4KEsUyG2vdoekip6 |
| Key screens canvas | `screens/project/*.dc.html` + `screens/project/canvas.json` | https://claude.ai/artifact/SHz8n4TrmZ8RkFohrtCiiz |
| App icon and logo | `brand/` | Owner-supplied, 1408×1408 |

The `.dc.html` frames are HTML mockups. They link the token CSS under `ds/xpath/...` and the logo through `/_blob/...` URLs, so they only render fully inside the artifact. Read them for structure, copy and states, and take values from `xp_tokens.dart`, never from inline styles.

## Chosen concepts (the canvas's recommendations, accepted by the owner)

| Screen | Concept | Main frame | State frames |
|---|---|---|---|
| Project overview | **1A Run Sheet ledger** | `Main.dc.html` | `Overview-A-Dark`, `Overview-A-Quiet` |
| Job view | **2A Graph over log** | `Job-A-Graph.dc.html` | `Job-A-Dark`, `Job-A-Failed`, `Job-A-Interrupted`, `Job-A-Cancel` |
| Release detail | **3A Two swimlanes** | `Release-A-Lanes.dc.html` | `Release-A-Dark`, `Release-A-BothLive`, `Release-A-Rejected`, `Release-A-NoKey` |
| Small frames | — | `Approvals-Inbox`, `Approval-Notification`, `MenuBar-Extra`, `Dispatch-Sheet` | — |

What each concept is:
- **1A:** the release in progress is the hero, drawn as a horizontal rail across the top. Under it, a ledger of flavors reads local → testing → live, and the console stays docked at the bottom like Xcode's debug area.
- **2A:** a pipeline graph sits above a step list and the log, so the parallel jobs stay visible while you read one log.
- **3A:** an App Store lane and a Play lane sit under the hero. Below them come the timeline, release notes, the forced-update reminder and the PR. The Merge button sits with the hero and says why it is disabled until both lanes are live.

Not chosen, kept for reference only: `Overview-B-Canvas`, `Overview-C-Timeline`, `Job-B-Navigator`, `Job-C-Timeline`, `Release-B-Timeline`, `Release-C-Checklist`.

## Behaviour fixed by the frames

- **Approvals:**
  - An approval never completes from a notification or the menu bar extra. "Review…" opens the confirmation sheet in the main window.
  - Approve uses ⌘↩ after an arming delay, and Return never approves.
  - The approval detail states "If you approve…", and the approval becomes void if the commit, version or flavor changes.
- **Dispatch:** the sheet previews which runner and slot each job lands on and which gates it hits. The button reads "Dispatch N jobs ⌘↩", and Return does not dispatch.
- **App Store rejection:** "New build, same version" takes the next free build number (3285 in the sample, because dev already used 3284).
- **Optional extras:** two things in the frames are marked optional because the engine doesn't return their data today. Build them only if the engine grows them:
  - **Failed-step "suggested fix" box:** there is no failure-diagnosis field. Candidate: a `StepFailed.hint`, which the step contract already has.
  - **Store vitals (adoption, crash-free %):** `Overview-Optional-Vitals` needs store analytics the engine doesn't fetch. This is out of scope for 1.0.

## Brand assets

The symbol is an outlined X whose lower-right stroke runs on as a path into a node, then an arrow: ink on paper, no accent colour. Everything below is generated from `source/appLogo-XPath-Light.png` with ImageMagick. The background and ink colours are the Run Sheet tokens: paper `#F6F5F1` / `#141412`, ink `#1B1B18` / `#ECEAE3`. At small sizes the strokes are thickened so the symbol survives: dilation radius 22 px at ≤20 px, 12 at ≤40 px, 6 at ≤96 px, measured on the 1408 px source.

| Path under `brand/` | Use |
|---|---|
| `source/` | The owner's original 1408 px icons and logos (light and dark). Kept untouched. |
| `symbol/xpath-symbol-{black,white,ink-light,ink-dark}.png` | Transparent symbol, trimmed, full resolution. For in-app use and as the master for anything new. |
| `icon/xpath-icon-{light,dark}-1024.png` | Flat square app icon: symbol at 60% width on paper. For stores, docs and the README. |
| `icon-composer/background-{light,dark}.png`, `symbol-layer.png` | Layers to drag into Apple's Icon Composer to make the macOS 26 `.icon` (default, dark, clear and tinted). Phase 18b. |
| `macos/AppIcon.appiconset/` | Classic macOS icon set (16 to 1024, rounded-square shape with a soft shadow, `Contents.json`). Copy it over `apps/xp_desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset` until the `.icon` exists. |
| `menubar/XPathTemplate.png`, `@2x` | Menu bar extra template image: pure black on transparent, 14 pt tall. The name ends in `Template` so macOS tints it. |
| `sidebar/xpath-sidebar.png`, `@2x` | The 15 px brand slot at the top of the sidebar. Black on transparent; tint it with `color.text.primary` at runtime. |
| `web/favicon-16.png`, `favicon-32.png`, `favicon.ico` | Favicons, for docs and the future web dashboard. |
| `web/social-preview{,-dark}-1280x640.png` | GitHub social preview, at GitHub's recommended size. |
| `preview/preview-sheet.png` | Check sheet: the icon at 1024, dark and 128 px; the 16 / 32 / 64 px icons, favicons, menu bar and sidebar renders. |

Still open: building the `.icon` in Icon Composer needs Xcode's Icon Composer app (manual, Phase 18b). The dark source icon's background was a blue-black; the generated dark assets use the token `#141412` instead.
