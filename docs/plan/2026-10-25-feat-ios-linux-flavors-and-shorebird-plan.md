---
title: "feat: iOS flavors and entry points on Linux runners, and the Shorebird iOS track"
type: feat
date: 2026-10-25
---

## feat: iOS flavors and entry points on Linux runners, and the Shorebird iOS track

> Follow-up to the [iOS-on-Linux plan](2026-10-22-feat-ios-builds-on-linux-plan.md) (its
> [Upstream work](2026-10-22-feat-ios-builds-on-linux-plan.md#upstream-work) and
> [Shorebird iOS on Linux](2026-10-22-feat-ios-builds-on-linux-plan.md#shorebird-ios-on-linux-to-decide)
> sections) and [ADR 0014](../adr/0014-ios-builds-on-linux.md).

## Overview

A Linux runner builds a flavored Flutter iOS app (`--flavor`) and an app with a non-default
Dart entry point (`--target`), with each flavor's bundle id, display name, icon set, launch
screen and entitlements. Most of the work is upstream in omarchy-apple-dev: done on the owner's
fork first and pinned by XPath, then sent upstream one feature per PR. XPath then passes the
flavor and target to the Linux backend, scans each flavor for what Linux still cannot build,
and stops narrowing flavored jobs to `ios-sign`. Shorebird iOS stays on a Mac until Shorebird
itself supports Linux; this plan files that request.

## Problem Statement / Motivation

The Phase 0 [blocker audit](2026-10-22-feat-ios-builds-on-linux-plan.md#blocker-audit-2026-10-25):

| App | Moves to Linux when |
|---|---|
| A | now |
| B (2 flavors, a launch screen per flavor, no `AppIcon` set) | flavors |
| C (4 flavors, 6 storyboards, 16 icon files, Shorebird) | flavors, storyboards, icons; Shorebird iOS |
| D (Dart entry points, CocoaPods, 22 icon files, Shorebird) | entry points, SwiftPM, single icon; Shorebird iOS |
| E | out of scope (a Dart SDK dev build) |

Every flavored or non-`lib/main.dart` job is narrowed to `ios-sign` today, and any storyboard
beyond Flutter's template narrows the whole app. omarchy-apple-dev's Flutter path has no
flavor support: it reads build settings from the first match in `project.pbxproj` whatever its
configuration (in a flavorizr project, the wrong bundle id, silently), passes no flavor and a
hardcoded `lib/main.dart` to `flutter assemble`, always uses the `AppIcon` set, and compiles
only `Base.lproj` storyboards.

## Proposed Solution

### Decisions

- **Flavors cover their assets:** configuration, xcconfig, bundle id, display name,
  `-dFlavor`, icon set and launch storyboard, per flavor, so B and C can move.
- **Fork first, then upstream.** Each upstream item lands on a branch of
  `AbdurahmanAlmehdi/omarchy-apple-dev`; XPath pins a fork commit, as PR 6 does; each proven
  item goes upstream as its own PR ("one fix or one feature per PR", its CONTRIBUTING.md). The
  pin moves to an upstream commit once all of them merge.
- **When a flavor stays on a Mac.** A flavor's job narrows to `ios-sign`, with the reason,
  only where a Linux build would succeed but differ from a Mac build:
  - a Run Script build phase in the Runner target other than Flutter's own (`xcode_backend.sh`
    build/embed, "Thin Binary"). The usual per-flavor `GoogleService-Info.plist` copy runs
    there; skipping it ships the wrong Firebase config or none. Applies to the whole app.
  - a multi-size app icon set for the flavor's configuration: it can leave App Store processing
    stuck with no error (omarchy-apple-dev `FINDINGS.md` item 68).

  What also fails on a Mac (no configuration or several matching the flavor, a missing icon
  set, a missing target file) is a warning finding, not a narrowing reason: the build fails
  the same way on either host.
- **A Linux build failure fails the job,** naming the file and flavor. No automatic retry on a
  Mac: a retry could upload twice.
- **Per-app opt-out.** A project edit turns Linux iOS builds off for one app. It is the rollback
  when a pin bump breaks one app, short of downgrading XPath, so it ships before the pin bump.
- **Findings are per flavor,** through the existing `Finding.flavor`
  (`xp_api/lib/src/finding.dart:59`); in a matrix over flavors, some on Linux and some on a Mac
  is valid and shown as such.

### Upstream work (omarchy-apple-dev, prerequisite)

Done on the fork with the project's own tests (Python `unittest` fixtures; extracted-block bash
tests with stub tools in `tests/run.sh`). Not built by `/build` in this repository.

- [ ] **U1. Build the chosen configuration.** Read the Runner target's `XCBuildConfiguration`
      by name (target over project, with its `baseConfigurationReference` xcconfig and
      includes) by reusing `tools/xcodeproj2xtool.py`'s parser, whose `config_settings`
      hardcodes `"Release"` (`:348`). `FLAVOR` selects the configuration with Flutter's own
      matching (`flutter_tools` `xcodeproj.dart:712-797`: scheme = sentence case, then
      `Release-<Scheme>`, exact then unique fuzzy match; none or several is an error listing
      the schemes). From it: `BUNDLE_ID`, `MIN_IOS`, device families, `gen-info-plist.py`'s
      settings and xcconfig, and `flutter assemble -dFlavor=<scheme> -dConfiguration=<config>`
      (Flutter then adds `FLUTTER_APP_FLAVOR` and flavor-scoped assets itself). `TARGET`, else
      the configuration's `FLUTTER_TARGET`, else `lib/main.dart`, becomes `-dTargetFile`.
      Likely two or three upstream PRs (settings, Info.plist, flavor and target). The
      CHANGELOG notes the change for projects whose first match was not Release.
- [ ] **U2. Icon set and storyboards per configuration.** `actool --app-icon` from the
      configuration's expanded `ASSETCATALOG_COMPILER_APPICON_NAME` (flavorizr writes
      `AppIcon-$(ASSET_PREFIX)`). Compile the storyboards the Runner target's
      `PBXResourcesBuildPhase` lists instead of globbing `Base.lproj`, and fail when the
      resolved `UILaunchStoryboardName` is not among them.
- [ ] **U3. Entitlements per configuration.** `ship.sh` uses the configuration's
      `CODE_SIGN_ENTITLEMENTS` when `ASC_ENTITLEMENTS_PATH` is not set.
- [ ] **U4. Signing with a given identity and profile.** The `ASC_PROFILE` mode PR 6 pins on
      the fork (`probe/runner_probe.dart:70-74` on #20), sent upstream like the rest.
- [ ] **U5. ibtool forms B and C use, only if they need them.** Check B's and C's launch
      screens against the Linux `ibtool` first. Candidates: flavorizr's opaque
      `genericGamma22GrayColorSpace` white (`tools/ibtool:345-360`) and flutter_native_splash's
      per-flavor background/branding storyboard. Each needs a golden made by Apple's ibtool on
      the owner's Mac (`tests/ibtool/compile-golden.sh`).
- [ ] **Pin.** A fork branch with these items and #82 on upstream main, pinned by full SHA
      with a tag, so a force-push or a deleted branch cannot lose it.

### Shorebird iOS

Shorebird's CLI refuses iOS off macOS (`apple_releaser_mixin.dart:18-21`,
`apple_patcher_mixin.dart:89-93`), which is easy to lift. The blocker is that its iOS
`gen_snapshot_arm64` and `analyze_snapshot_arm64` are macOS binaries built from Shorebird's
**private** Dart fork (`shorebirdtech/dart-sdk` in `shorebirdtech/flutter` `DEPS:20-21`), and
upstream Dart's `gen_snapshot` lacks the linker flags and snapshot hash Shorebird's updater
checks. So a fork is not viable; Shorebird iOS stays on `ios-sign` until Shorebird ships Linux
support, and C and D keep a Mac for it.

- [ ] **S1. File the feature request** on `shorebirdtech/shorebird` (template
      `feature_request.md`) and in Discord: `ios-release/linux-x64.zip` (and arm64) with
      `gen_snapshot_arm64` and `analyze_snapshot_arm64`, as they publish
      `android-*-release/linux-x64.zip`; Linux allowed for iOS release and patch, or an
      external-builder mode taking an xcarchive, `app.dill` and the supplement; `xcodeVersion`
      optional; whether Linux- and Mac-hosted output is byte-identical (a patch must match its
      release's `gen_snapshot` build). Offer the omarchy-apple-dev approach and testing; ask
      whether a modified CLI may use their API. Link the issue here.

## Technical Considerations

- **Pin and fleet.** The pin is an exact commit (`probe/runner_probe.dart:75` and `:372` on
  #20), so every `ios-linux` runner is at it, and lifting a narrowing case in the release that
  bumps the pin is safe for placement. Runners left at the old commit lose `ios-linux`; a job
  that was not narrowed then waits with the scheduler's "No runner can do …"
  (`scheduler.dart` ~402). That wait reason and the dry run should name the runners' missing
  `ios-linux` and its fix (`git -C <dir> checkout <pin>`), which `Runner.missing`
  (`MissingCapability`) already carries.
- **Where limits live.** Whole-app limits stay on `AppProfile.iosLinuxLimits`
  (`xp_api/lib/src/project_profile.dart:389` on #20); per-configuration ones go on a new
  `FlavorProfile.iosLinuxLimits` (`project_profile.dart:188`), carried through
  `FlavorProfile.copyWith` so `applyEdits` does not drop it. `iosLinuxLimits(steps, app)` finds
  the flavor from the step's `input['flavor']`, so `_narrow` is unchanged. Every reason is
  listed: App D will still narrow on CocoaPods after entry points land.
- **Signing.** No change to D-09. PR 6 already resolves each flavor's identity, bundle id and
  engine-made profile; U3 makes its entitlements the flavor's own.

## Dependencies

- PR 6 (#20) merged: the Linux backend, narrowing, the pin and per-flavor signing.
- Phase 3 needs U1-U4 and the pin on the fork. Phase 4's receipts need U5 where B or C uses it.

## Implementation Phases

`/build` runs these in order, one per context window.

### Phase 1: Per-app opt-out

- **Status:** Done
- **Scope:** `AppEdit.iosLinux` (bool, default on) in `ProfileEdits`, applied to
  `AppProfile.iosLinux`; when off, `iosLinuxLimits` narrows every iOS job of the app with
  "Linux iOS builds are turned off for this app". Edits are stored as JSON in the project's
  `edits` column, so no migration. CLI and MCP descriptions updated; no desktop change (the
  desktop edits only store ids). ADR 0014 gets an "## Amendment" (as ADR 0011 does).
- **Files touched:** `packages/xp_api/lib/src/profile_edits.dart`,
  `packages/xp_api/lib/src/project_profile.dart` (+ `.g.dart`), `packages/xp_api/openapi.yaml`,
  `packages/xp_engine/lib/src/projects/apply_edits.dart`,
  `packages/xp_engine/lib/src/dispatch/ios_linux_limits.dart`,
  `apps/xp/lib/src/commands/projects_commands.dart`, `apps/xp/lib/src/mcp/xp_tools.dart`,
  `docs/adr/0014-ios-builds-on-linux.md`, `packages/xp_api/test/contract/shipped_openapi_test.dart`,
  `apps/xpd/test/contract/`, tests
- **Acceptance criteria:** with the opt-out off, every iOS job of the app narrows with that
  reason and the dry run shows it; `PATCH /projects/{id}` round-trips it; edits made before
  this change still apply.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase 2: Per-flavor limits in the scan

- **Status:** Not started
- **Scope:** The scan finds the two narrowing cases (non-Flutter Run Script phases, app-wide;
  a multi-size icon set, per flavor) and the warnings (no or several configurations for a
  flavor, a missing icon set), as `ios_needs_mac` findings with `Finding.flavor`, and
  `iosLinuxLimits` narrows on them. The flavor narrowing case stays until Phase 3.
- **Files touched:** `packages/xp_engine/lib/src/scan/xcode_project_parser.dart` (shell-script
  and resources build phases, `baseConfigurationReference`),
  `packages/xp_engine/lib/src/scan/app_scanner.dart`, `packages/xp_api/lib/src/project_profile.dart`
  (+ `.g.dart`), `packages/xp_api/openapi.yaml`, `packages/xp_engine/lib/src/dispatch/ios_linux_limits.dart`,
  fixtures in `tool/e2e/fixtures/` (flavorizr-style, flutter_native_splash-style, a Run Script
  copying `GoogleService-Info.plist`), `packages/xp_engine/test/scan/goldens/` (all regenerate
  with `UPDATE_GOLDENS=1 dart test test/scan/fixtures_test.dart`),
  `packages/xp_api/test/src/project_profile_test.dart`, contract tests
- **Acceptance criteria:** the flavorizr fixture reports each flavor's limits and the resolved
  configuration in the finding text; a Run Script phase narrows every flavor and a multi-size
  set narrows only its flavor; the stock template reports nothing.
- **Validation:** `melos run test:coverage && melos run test:contract`

### Phase 3: Flavor and target reach the Linux backend

- **Status:** Not started
- **Scope:** The Linux `build.ios` passes `FLAVOR` and `TARGET` to `flutter/build.sh` and
  `FLAVOR` to `flutter/ship.sh`, and stops passing `ios/Runner/Runner.entitlements` (U3). The
  pin moves to the fork commit with U1-U4. The flavor and entry-point narrowing cases, the
  scan's `flavorsLimit` and its blanket non-template storyboard limit are removed: an
  unsupported storyboard now fails the build with ibtool's error, and the opt-out is the escape
  hatch. The wait reason for runners at an old pin names the fix.
- **Files touched:** `packages/xp_engine/lib/src/steps/build/build_ios.dart`,
  `packages/xp_engine/lib/src/dispatch/ios_linux_limits.dart`,
  `packages/xp_engine/lib/src/scan/app_scanner.dart`, `packages/xp_engine/lib/src/probe/runner_probe.dart`,
  `packages/xp_engine/lib/src/scheduler/scheduler.dart`, `tool/e2e/runner_ios_linux_e2e.sh` and
  `tool/e2e/build_app` (a flavored stub app), tests
- **Acceptance criteria:** a flavored job with no limits plans onto `ios-linux` with `FLAVOR`
  and `TARGET` in the stubbed scripts' environment; two flavors of one app on one runner
  (slots 2) build in separate directories; a job waiting only on old-pin runners says which
  runners and the checkout command.
- **Validation:** `melos run test:coverage && tool/e2e/runner_ios_linux_e2e.sh`

### Phase 4: Docs and receipts

- **Status:** Not started
- **Scope:** Docs say what flavors on Linux support and what still needs a Mac; ADR 0014's
  amendment records that a Shorebird fork is not viable; the parent plan's upstream items are
  ticked; one TestFlight build per flavor of B and C (C as plain builds; its releases use
  Shorebird), recorded in the PR description.
- **Files touched:** `docs/guide/runners.md`, `docs/adr/0014-ios-builds-on-linux.md`,
  `docs/plan/2026-10-22-feat-ios-builds-on-linux-plan.md`, this plan
- **Acceptance criteria:** each flavor of B and C installs from TestFlight built on Linux with
  its own icon, launch screen, display name and Firebase project.
- **Validation:** `manual 1. On a Linux runner at the pin, dispatch a TestFlight build of each flavor of B and C. 2. Install each from TestFlight; check icon, launch screen, display name, Firebase project, push and deep links. 3. Record build number, flavor and pin in the PR description.`

## Success Criteria

```success-criteria
GOAL: Linux runners build, sign and upload flavored Flutter iOS apps and non-default entry points with each flavor's own settings and assets, and send to a Mac, with a reason, only what a Linux build would get wrong.

SUCCESS CRITERIA:
- The per-app opt-out narrows every iOS job of the app with its reason | verify: melos run test:coverage
- The scan reports per-flavor limits and warnings through Finding.flavor, and narrowing follows them | verify: melos run test:coverage
- The profile and edit fields are in openapi.yaml and covered by contract tests | verify: melos run test:contract
- A flavored or non-default-target job without limits runs on ios-linux with FLAVOR and TARGET passed to the scripts | verify: tool/e2e/runner_ios_linux_e2e.sh
- Analyzer, format and the layer check pass | verify: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart
- Each flavor of apps B and C installs from TestFlight built on Linux, with its own icon, launch screen, display name and Firebase project | verify: manual 1. Run Phase 4's validation. 2. Check the PR description lists every flavor.
- The Shorebird feature request is filed and linked in this plan | verify: manual 1. Open the S1 link. 2. Confirm it asks for Linux iOS gen_snapshot/analyze_snapshot and an external-builder mode.

NON-GOALS:
- Shorebird iOS on Linux (blocked on Shorebird; a new plan if they ship it).
- App extensions, CocoaPods-only plugins, alternate icons, debug or profile builds on Linux.
- Moving apps to a single-size icon or SwiftPM plugins (app-side work); app E.

VERIFICATION COMMAND: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract && tool/e2e/runner_ios_linux_e2e.sh
```

## Success Metrics

- Apps B and C (non-Shorebird builds) ship TestFlight builds from Linux only.
- No flavored build ships with another flavor's bundle id, icon or Firebase config.

## Risks

- **Upstream drift.** The fork pin keeps XPath moving, but items may land upstream differently;
  rebase the pin branch on each upstream merge.
- **ibtool goldens need a Mac.** Launch screens without a golden are checked by eye in the
  receipts.
- **U1 changes behaviour** for projects whose first pbxproj match was not Release.
- **Run Script phases** are common in Firebase flavor setups; B or C may stay on a Mac until
  the app copies its per-flavor plist another way. Check them first.

## References & Research

- omarchy-apple-dev (upstream main, 2026-10-25): `flutter/build.sh:46-137`,
  `flutter/tools/gen-info-plist.py:20-113`, `tools/xcodeproj2xtool.py:156-361`,
  `tools/ibtool:345-360,4477-4499`, `tools/darwin-tools/Sources/actool/CatalogMerge.swift:71-76`,
  `SingleSizeIcon.swift:20-125`, `FINDINGS.md:1644-1656`, CONTRIBUTING.md:30-36; #81 merged as
  `7e528cc`, #82 open.
- Flutter `flutter_tools`: `xcodeproj.dart:712-797`, `build_info.dart:345`,
  `xcode_backend.dart:699-702`, `common.dart:316-352`, `ios.dart:709-731`.
- Shorebird: CLI `69b2915`, `shorebirdtech/flutter` `ab86e95` (`DEPS:20-21`), issues
  [#2105](https://github.com/shorebirdtech/shorebird/issues/2105),
  [#3695](https://github.com/shorebirdtech/shorebird/issues/3695),
  [#3892](https://github.com/shorebirdtech/shorebird/issues/3892); Code Push Terms §E.
- XPath on #20: `dispatch/ios_linux_limits.dart`, `dispatch/workflow_dispatcher.dart:165-170,982-1010`,
  `steps/build/build_ios.dart:179-292`, `scan/app_scanner.dart:249-345`,
  `scan/xcode_project_parser.dart`, `projects/apply_edits.dart`, `xp_api/lib/src/profile_edits.dart`.
