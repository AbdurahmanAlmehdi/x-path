---
title: "feat: iOS builds on Linux runners via omarchy-apple-dev"
type: feat
date: 2026-10-22
---

## feat: iOS builds on Linux runners via omarchy-apple-dev - Extensive

> Consolidated from the 2026-10-22 plan on branch `claude/lucid-brown-hm4646` (commits
> `81c1af7`, `f5057f3`, `9fd614c`). It is checked against the
> [runner onboarding plan](2026-10-22-feat-remote-runner-onboarding-plan.md) and the
> [UX plan](2026-10-22-feat-ux-improvements-plan.md); see [Related plans](#related-plans). The
> decision record is [ADR 0014](../adr/0014-ios-builds-on-linux.md) (Proposed).

> **Note:** This plan was split into parts for building. See the -part-N files in this
> directory; run `/build` on a part file, one pull request per part, never on this file.

## Overview

Today every iOS step needs a Mac with Xcode, and because `upload.appStore` needs `ios-sign` and
only runs on the engine, the engine must be a Mac too. This plan lets a release workflow, iOS
steps included, run on Linux, using
[omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev) as the Linux iOS
toolchain. It is opt-in and experimental per runner; Macs keep working as they do.

## Goal

Set up once, then trigger and approve releases remotely on a Linux machine, with no Mac in the
loop: not for a build step, not for setup. A job that needs a Mac part-way through does not
meet the goal. So:

- The plan-time narrowing to `ios-sign` (Phase 3a) is a safety net, not the design. For the
  apps this is for, every narrowing case that applies is a prerequisite to remove upstream
  before the move, not a step left on a Mac.
- Setup needs no Mac either: `Xcode.xip` is downloaded in a browser on any OS, and the Apple
  Distribution certificate is created through the App Store Connect API on Linux (Phase 4b): a
  new one, rather than exporting the Mac's from Keychain. Apple limits how many a team has, so
  check the count first.
- Releases are triggered and approved with `xp` (or an agent over `xp mcp`, which can request
  but never approve, D-13) against the Linux engine, reached remotely through TLS as for any
  remote engine (the runner plan's R4 and R6).

## Problem Statement

### Where XPath is Mac-bound today

| Blocker | Where |
|---|---|
| `ios-sign` is probed only on macOS with `xcode-select` and `xcodebuild` | `xp_engine/lib/src/runners/runner_probe.dart`, `scheduler/local_capabilities.dart` |
| Each iOS step fails when `isMacOS` is false | `steps/build/build_ios.dart`, `steps/build/strip_and_reexport.dart`, `steps/upload/upload_app_store.dart`, `steps/shorebird/shorebird_release.dart`, `steps/shorebird/shorebird_patch.dart` |
| Upload is `xcrun altool`; `upload.appStore` needs `ios-sign` and is engine-only | `steps/upload/upload_app_store.dart`, `dispatch/step_planners.dart`, `runners/remote_step_policy.dart` (D-09, D-14) |
| No credential kind for a signing identity; a runner is granted only keystore and Shorebird secrets | `xp_api/lib/src/credential.dart`, `runners/runner_secret_grants.dart` (D-09, ADR 0012) |
| The IPA is read from `build/ios/ipa/*.ipa`; dSYMs from the Xcode archive | `steps/build/build_outputs.dart`, `steps/symbols/symbols_archive.dart` |
| Capabilities are a flat all-of set | `scheduler/capability.dart`, `scheduler/scheduler.dart` (`_place`) |
| Every flavored app builds with `--flavor` | `steps/build/build_settings.dart:112` |
| The runner service passes only `--data-dir` and `--slots` | `apps/xp/lib/src/runner/service/runner_service.dart:45-50` |

### What omarchy-apple-dev provides

omarchy-apple-dev (MIT) builds, signs and uploads iOS apps on Linux with Swift 6.4, xtool,
SwiftBuild, a darwin SDK cut from a user-supplied `Xcode.xip`, rcodesign and the App Store
Connect API. Its Flutter path does not run `flutter build ipa`: it runs `flutter assemble` with
a Linux-hosted `gen_snapshot` and shims, builds Runner and the plugins as one SwiftPM package,
and compiles icons and storyboards with its own `actool` and `ibtool`.

The pieces this plan relies on were contributed upstream for it:

| Upstream PR | What it adds | State |
|---|---|---|
| #72 | `flutter/ship.sh [--upload] <app>`: stamp, sign, validate and upload a `flutter/build.sh` build | Merged |
| #73 | `SPLIT_DEBUG_INFO` and `DART_OBFUSCATION` for `flutter/build.sh` | Merged |
| #74 | `build/ios-linux/dSYMs`, one dSYM per image | Merged |
| #75 | `STRIP_FRAMEWORKS` for `flutter/build.sh` | Merged |
| #76 | `ASC_EXPORT_OPTIONS`: an Xcode `ExportOptions.plist` for `asc.py identity` | Merged |
| #77 | Strip refuses frameworks loaded through `@executable_path` / `@loader_path` (owner's fix to #75) | Merged |
| #81 | `gen-info-plist.py` expands `$(...)` settings from `Flutter/Release.xcconfig` and its includes (found in Phase 0) | Open |
| #82 | `install-toolchain.sh` no longer copies `libXADI.so`, which xtool 1.23.0 does not build, and repairs a half-done install (found in Phase 0) | Open |

The interface XPath calls (all scripts exit non-zero on failure; none prints JSON):

```sh
flutter/setup.sh                                   # once per Flutter version (~7 GB, 5-12 min)
BUILD_NAME=… BUILD_NUMBER=… SPLIT_DEBUG_INFO=… DART_OBFUSCATION=true STRIP_FRAMEWORKS="A B" \
  flutter/build.sh <app> KEY=VALUE …               # -> build/ios-linux/Payload/Runner.app, dSYMs/
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=… ASC_EXPORT_OPTIONS=… ASC_ENTITLEMENTS_PATH=… \
  flutter/ship.sh [--upload] <app>                 # -> build/ios-linux/Runner-store.ipa
```

### What is still not possible on Linux

These stay on a Mac, or narrow the job to a Mac with a clear reason:

- **Needs Apple hardware or the Apple portal:** the iOS Simulator, Flutter macOS apps and the
  XPath DMG, Instruments, creating the App Store Connect app record. Integration tests and
  screenshots are not offered on iOS in a Linux workflow; they run on an Android emulator
  instead (see [No iOS Simulator in Linux workflows](#no-ios-simulator-in-linux-workflows)).
- **Not built yet:** Shorebird iOS; debug and profile builds; flavors (build configurations);
  plugins without a `Package.swift` (CocoaPods only); app extensions; entitlements beyond
  Associated Domains, push, Sign in with Apple and best-effort app groups; storyboards beyond
  Flutter's template; multi-size and alternate app icons; ad hoc and enterprise distribution;
  Apple ID password uploads; Flutter older than 3.47 (3.47.6 is the verified version). Flavors,
  extensions, storyboards and icons are delegated upstream; Shorebird iOS has its own track
  (see [Upstream work](#upstream-work)).
- **Built but not yet run on a real build:** obfuscation with the Linux `gen_snapshot`,
  strip-frameworks on a real app, export options against App Store Connect. Full Xcode-SDK mode
  is tested on Arch/Omarchy only. A full-mode Flutter upload through `flutter/ship.sh` and dSYMs
  from a real SwiftBuild ran in Phase 0.

## Proposed Solution

- **Uploads through the App Store Connect API** on any engine (Phase 1). This is useful on its
  own: it removes altool for API-key flavors on Macs too, and lets a Linux or Docker engine
  upload iOS builds.
- **An opt-in `ios-linux` capability.** `ios-sign` keeps meaning a Mac with Xcode, so existing
  workflow YAML is unchanged. A runner reports `ios-linux` (Phase 2) and the scheduler learns
  any-of placement (Phase 3a) before any step accepts it; only Phase 3b, which ships the Linux
  backend, signing already in place (Phase 4a), lets `build.ios` run there. No runner receives
  an iOS job it cannot build.
- **The same steps, a backend per host.** `build.ios` accepts either capability; on Linux it
  calls omarchy-apple-dev's scripts (Phase 3b).
- **Jobs that Linux cannot build go to a Mac**, decided by the planner from the job's inputs,
  never discovered mid-build.
- **XPath never downloads Apple software.** The user installs omarchy-apple-dev and supplies
  `Xcode.xip`; XPath probes, pins and records the toolchain.

### Decision: who creates the App Store profile for a Linux build

Decided 2026-10-25, recorded in ADR 0014: **(b)**.

- **(b) Chosen.** The engine creates the profile with its own App Store Connect client and
  sends only the identity and the profile to the runner, which signs with rcodesign. The ASC
  key stays on the engine (D-09 unchanged). Needs a small upstream change so `asc.py identity`
  (or `flutter/ship.sh`) takes a given profile.
- **(a) Rejected.** The App Store Connect key goes to the runner for the job, and
  omarchy-apple-dev's `asc.py identity` creates the certificate and profile. Least code, but it
  widens D-09, under which ASC keys never leave the engine.

## Technical Approach

### Architecture

- **Where a job goes.** The planner decides from the job alone which capabilities can build
  it, before any runner is chosen:
  - `build.ios` and `ios.stripAndReexport` need any of `{ios-sign, ios-linux}`.
  - The planner **narrows** that to `ios-sign` when the job uses something the Linux path
    cannot build: a Flutter `--flavor` (`build_settings.dart:112`), Shorebird iOS, a debug or
    profile build, an app extension, or an iOS Simulator target. Each narrowing records its
    reason, naming the upstream task that would lift it.
  - The job **fails at plan time** only when no paired runner (online or not) offers a
    capability left in its set. Otherwise it waits, and its queue message says why `ios-linux`
    was ruled out ("needs ios-sign: the app uses the flavor prod, which Linux iOS builds do not
    support yet").
  - With both kinds free, the scheduler prefers a Mac. The one-iOS-job-per-machine rule
    applies to both.
  - The narrowing reasons are among the UX plan's U2c dry-run skipped or placement reasons.
- **Probe model.** `ios-linux` uses the runner plan's R1 `MissingCapability{reason, fix}`. A
  runner not configured for Linux iOS does not list `ios-linux` as missing (it is opt-in, like
  a capability for another OS). A configured runner lists every failed check.
- **Configuration that survives restarts.** The omarchy-apple-dev directory is the environment
  variable `XP_IOS_LINUX_DIR`, read by `xp runner start` and `xp runner doctor`.
  `xp runner install-service` writes it into the unit when it is set at install time, as the
  runner plan's R7 does for `ANDROID_HOME`, so it is not lost when the service passes only
  `--data-dir` and `--slots` (`runner_service.dart:45-50`). No new config surface until the
  feature is accepted. The runner sends the directory's probe commands with its probe results,
  because the engine's probe list is fixed in `xp_engine`.
- **Pinned upstream.** Each XPath release pins one omarchy-apple-dev commit. The probe compares
  the checkout's commit with the pin. When a runner self-updates to an engine with a newer pin,
  `ios-linux` is lost with the reason "omarchy-apple-dev is at `<a>`; this XPath needs `<b>`"
  and the fix `git -C <dir> fetch && git -C <dir> checkout <b>`, printed and logged as the
  runner plan's R1 and R3 do.

## Implementation Phases

| Phase | Needs | Can start |
|---|---|---|
| 0. ADR and a spike on real hardware | an Omarchy machine, a real app | now |
| 1. App Store upload through the API | — | now, in parallel with Phase 0 |
| 2. Report the `ios-linux` capability | runner plan R1, R2 | after R2 |
| 3a. Any-of placement and narrowing (no behaviour change) | Phase 2 | after Phase 2 |
| 4a. Signing identity and profile on a Linux runner | profile decision (made: (b)); runner plan R10a's foreign-keys-off migrations, or its own | after the gate |
| 3b. The Linux build backend and toolchain preparation | Phase 0 gate, 3a, 4a | after the gate |
| 4b. Signing set-up without a Mac | 4a | after 4a |
| 5. Scan, dry run and docs | 3b; UX plan U2c for the dry run; runner plan R4 for `docs/guide/runners.md` | after 3b |

Every phase that changes the API updates `openapi.yaml` and adds a contract test in
`apps/xpd/test/contract/`, and every schema change is a migration with its snapshot golden.

### Phase 0: ADR and a spike on real hardware (no product code)

- **Status:** Done (2026-10-25)
- **Scope:** Prove the toolchain on a real app before XPath depends on it.
- **Files touched:** `docs/adr/0014-ios-builds-on-linux.md`, a spike workflow kept outside the
  repo, the receipt recorded in this plan
- **Acceptance criteria:** a build of a real app made with `flutter/setup.sh`,
  `flutter/build.sh` and `flutter/ship.sh --upload` reaches `VALID` in App Store Connect and
  installs from TestFlight. Record which of the "not built yet" items the app hit.
- **Validation:** `manual 1. On an Omarchy machine with install-toolchain.sh done, run a workflow of command steps calling setup.sh, build.sh and ship.sh --upload on a real app. 2. Wait for VALID in App Store Connect. 3. Install from TestFlight. 4. Record the build number, the omarchy-apple-dev commit and the items hit in this plan.`

- [x] ADR 0014 accepted (the profile decision, (b), is already recorded in it).
- [x] Blocker audit of each app that is to move: flavors, plugins without a `Package.swift`,
      app extensions, entitlements, storyboards, app icons, Shorebird use. The result orders
      the [Upstream work](#upstream-work) list; an app moves only when its list is empty.
- [x] The spike above, on an app with no Flutter flavors, no Shorebird and no extensions.
- [x] **Gate:** do not start Phase 3b before this passes on at least one app. Passed on
      2026-10-25; the receipt is below.

#### Receipt (2026-10-25)

Shell commands, not an XPath workflow; the scripts and their output are the same.

| | |
|---|---|
| Machine | EC2 c7i.4xlarge (16 vCPU, 32 GB), x86_64 Arch Linux (Uplink Labs AMI 2026.10.15), `yay` from the AUR |
| Toolchain | Swift 6.4.1 (AUR `swift-bin`; the README table says 6.4.0), xtool `f300489`, rcodesign 0.29.0, Xcode 27.0 (27A266a) `.xip`, Flutter 3.47.6 |
| omarchy-apple-dev | `955127b` plus #81 at `b73b48a` and #82's one-line fix (fork `AbdurahmanAlmehdi/omarchy-apple-dev`) |
| App | a real app with an App Store Connect record: 17 plugins over SwiftPM, push, Sign in with Apple, Associated Domains, Firebase, Google Sign-In; no flavors, no extensions |
| `flutter/setup.sh` | 2 min 44 s |
| `flutter/build.sh` | 2 min 15 s, `BUILD_NAME=1.0.3 BUILD_NUMBER=10` and two dart defines; 7 dSYMs |
| `flutter/ship.sh --upload` | `ASC_ENTITLEMENTS_PATH=ios/Runner/Runner.entitlements`; 52/52 offline checks; `buildUpload 23a656bd-be08-4a2c-be7e-0982ffd9d55f` `COMPLETE` |
| Result | build 1.0.3 (10) `VALID` within minutes; installed from TestFlight on an iPhone; Google and Apple sign-in work |

"Not built yet" items the app hit, and what else came up:

- **Multi-size app icon.** The app had 25 legacy sizes; it moved to Xcode's single 1024 px
  icon in the app's own repository. No upstream change was needed.
- **Entitlements are not read by default.** `ASC_ENTITLEMENTS_PATH` had to be passed by hand;
  `asc.py` then signed push (as `production`, as Xcode does), Sign in with Apple and Associated
  Domains. Still an open item in [Upstream work](#upstream-work).
- **Info.plist settings from the app's own xcconfig.** `$(GOOGLE_IOS_CLIENT_ID)` and the
  reversed id came from `Flutter/Google.xcconfig` and were written as empty strings, so Google
  sign-in would have failed at run time. Fixed upstream in #81.
- **Fresh install failed at the xtool step** (`libXADI.so`, gone since xtool 1.23.0). Fixed
  upstream in #82.
- **A storyboard beyond Flutter's template compiled.** The launch screen made by
  flutter_native_splash (a background image and edge constraints) needed no change.
- **One Apple Distribution certificate per machine.** `asc.py identity` creates a certificate
  on first use and keeps its key on that machine; the team was at its limit of three
  distribution certificates, and one had to be revoked. This supports the profile decision (b):
  runners must not each create their own certificate.

#### Blocker audit (2026-10-25)

Five apps that could move, checked by reading each iOS project (names left out):

| App | Flavors | Plugins without `Package.swift` | Extensions | Entitlements | Storyboards | App icon | Shorebird | Moves when |
|---|---|---|---|---|---|---|---|---|
| A (the Phase 0 app) | none | none (SwiftPM) | none | push, Sign in with Apple, Associated Domains | template `Main`, flutter_native_splash launch screen | single 1024 px | `shorebird.yaml`, plain release builds | now |
| B | 2 (schemes and bundle ids) | none (SwiftPM) | none | none | a launch screen per flavor | no `AppIcon` set in Runner | no | flavors |
| C | 4 | none (SwiftPM) | none | none | 6 (a launch screen per flavor) | 16 files | yes | flavors, storyboards, icons, Shorebird iOS |
| D | Dart entry points only (no iOS flavors) | CocoaPods; not checked per plugin | none | push, Sign in with Apple, Associated Domains | `Main` and `LaunchScreen`, not compared with the template | 22 files | yes | SwiftPM, single icon, Shorebird iOS |
| E | Dart entry points only | CocoaPods | none | push, Sign in with Apple, Associated Domains | `LaunchScreen` only | 2 files | no | out of scope: a Dart SDK dev build |

This orders [Upstream work](#upstream-work): flavors first (B and C), then Shorebird iOS (C and
D). The icons are app-side fixes, as in A.

### Pull requests

These phases are built from the part files, one `/build` run and one pull request each.
Their full text, with the `Status` markers `/build` updates, is in the part files only.

| PR | Part file | Contains |
|---|---|---|
| 1 | [Runner core](2026-10-22-feat-remote-runner-onboarding-part-1-plan.md) | R1–R9 |
| 2 | [Projects on any git host](2026-10-22-feat-remote-runner-onboarding-part-2-plan.md) | R10a–R10d |
| 3 | [UX part 1](2026-10-22-feat-ux-improvements-part-1-plan.md) | U1a-1 to U4c |
| 4 | [UX part 2](2026-10-22-feat-ux-improvements-part-2-plan.md) | U5a to U8 |
| 5 | [iOS on Linux part 1](2026-10-22-feat-ios-builds-on-linux-part-1-plan.md) | Phases 1, 2, 3a |
| 6 | [iOS on Linux part 2](2026-10-22-feat-ios-builds-on-linux-part-2-plan.md) | Phases 4a, 3b, 4b, 5 |

Order: PR 1 first. Then PRs 2, 3 and 5, in parallel. Then PRs 4 and 6.

| Part | Phases |
|---|---|
| (not a PR) | Phase 0, below: the ADR and the real-hardware test, the gate for Phase 3b |
| [Part 1](2026-10-22-feat-ios-builds-on-linux-part-1-plan.md) | 1, 2, 3a |
| [Part 2](2026-10-22-feat-ios-builds-on-linux-part-2-plan.md) | 4a, 3b, 4b, 5 |

## No iOS Simulator in Linux workflows

XPath has no Simulator step: `test` runs `flutter test` on the host, which works on Linux.
Integration tests and screenshots that need a device run on an Android emulator; iOS ones are
not offered when the iOS build runs on Linux. A `command` step that calls `xcrun simctl` needs
`ios-sign`, and the docs say so. If a device-test or screenshot step kind is added later, it
narrows an iOS target to `ios-sign` like the other cases in Phase 3a.

## Upstream work

> Flavors, entry points and their icons and launch screens are planned in
> [iOS flavors on Linux](2026-10-25-feat-ios-linux-flavors-and-shorebird-plan.md).

Delegated to omarchy-apple-dev (one feature per PR, as its CONTRIBUTING.md asks). Until each
lands, XPath's scan reports the app as needing a Mac for iOS, and the planner narrows the job
to `ios-sign` with the reason. Each item is done when it is merged upstream, pinned by XPath,
and the matching narrowing case is removed.

The items ticked below are done on the fork pin: `2d03f766859e6e4549b949b4afbb8e66d851b18d`
(`2d03f76`) on the `xpath/pin-flavors` branch of `AbdurahmanAlmehdi/omarchy-apple-dev`, tag
`xpath-pin-flavors-1`, which is upstream main `ceda63a` plus these items. XPath pins it and has
removed their narrowing cases. They went upstream as joshuaswarren/omarchy-apple-dev #85-#89, all
merged, and the pin has moved to upstream main `79bda71`.

- [x] **Flavors (build configurations and schemes).** `flutter/build.sh` takes the first
      `PRODUCT_BUNDLE_IDENTIFIER` in the pbxproj. It needs the `Release-<flavor>` configuration
      and its xcconfig (bundle id, display name, `$(...)` settings in Info.plist) and
      `-dFlavor` for `flutter assemble`. XPath then maps `--flavor` to it. The largest blocker,
      since every flavored app passes `--flavor`. Done with `FLAVOR` and `TARGET` (entry points)
      on the fork pin.
- [ ] **App extensions** (widgets, share, notification service) in the Flutter path: build each
      target as its own product, embed it under `PlugIns/`, sign it with its own profile.
      `asc.py identity` and the top-level `ship.sh` already handle `PlugIns/*.appex`.
- [x] **Storyboards the Runner target lists.** The storyboards of its Copy Bundle Resources
      phase are compiled, not only `Base.lproj`, so a launch screen per flavor builds.
- [ ] **Storyboards beyond Flutter's template.** The Linux `ibtool` stops on a feature it does
      not compile; each missing feature is a change there. Such a storyboard now fails the build
      with ibtool's error instead of narrowing the app.
- [x] **The icon set of each configuration** (`ASSETCATALOG_COMPILER_APPICON_NAME`), not always
      `AppIcon`.
- [ ] **Multi-size and alternate app icons.** A multi-size AppIcon can leave App Store
      processing stuck; alternate icons are dropped. Both are `actool` work.
- [x] **The entitlements of each configuration** (`CODE_SIGN_ENTITLEMENTS`), used when
      `ASC_ENTITLEMENTS_PATH` is not set, so the default `ios/Runner/Runner.entitlements` path
      is no longer passed.
- [ ] More entitlements than Associated Domains, push, Sign in with Apple and app groups.
- [ ] A checker that lists plugins without a `Package.swift`, for the scan.
- [x] A receipt for a full-mode Flutter TestFlight upload with `flutter/ship.sh` (Phase 0;
      posted on #81).
- [x] #81 (Info.plist settings from the app's xcconfig) and #82 (installer) merged, then pinned.
      #81 merged as `7e528cc`; both are in upstream main `ceda63a`, which the fork pin is on.
- [x] `asc.py identity` or `flutter/ship.sh` takes a given profile (profile decision (b)).
      Written as `asc.py given-identity` (`ASC_PROFILE`, `ASC_SIGNING_KEY`, `ASC_SIGNING_CERT`)
      on the fork pin, and sent upstream with the other items.
- [ ] #73 and #77 pinned (both merged).

### Shorebird iOS on Linux (to decide)

> Decided in [iOS flavors on Linux](2026-10-25-feat-ios-linux-flavors-and-shorebird-plan.md#shorebird-ios):
> a feature request to Shorebird; a fork is not viable (Shorebird's Dart fork is private).

`shorebird release ios` and `shorebird patch ios` need macOS today: the Shorebird CLI refuses
iOS elsewhere, and a release and its patches are built with Shorebird's own engine and Dart
fork, whose iOS `gen_snapshot` and patch tools are macOS binaries. omarchy-apple-dev solves the
same problem for stock Flutter by building a Linux-hosted `gen_snapshot` from the Dart SDK at
Flutter's pinned revision.

- [ ] Decide between:
  - **A feature request to Shorebird** for Linux-hosted iOS releases and patches, offering the
    omarchy-apple-dev approach and our help. Nothing to maintain; depends on their priorities.
  - **Our own fork** of the Shorebird CLI plus a Linux build of Shorebird's iOS `gen_snapshot`
    and patch tools. Works on our schedule, but has to be rebuilt and checked for every
    Shorebird and Flutter release, and a patch must be byte-compatible with what Shorebird's
    updater expects.
  - Recommended order: the feature request first; a fork only if it is declined and Linux
    Shorebird iOS is still needed. Check the licences of the CLI and the engine fork first.
- [ ] Until then Shorebird iOS keeps requiring `ios-sign` (a Mac).

## Alternative Approaches Considered

- **Redefine `ios-sign` to include Linux.** Rejected: existing workflows that rely on Xcode
  features would land on Linux runners and fail.
- **Ship the darwin SDK or download `Xcode.xip` for the user.** Rejected: XPath does not
  redistribute or fetch Apple software.
- **Report `ios-linux` and place jobs in the same early PR.** Rejected: a runner would receive
  `build.ios` before the Linux backend exists and fail mid-build on `isMacOS`.
- **Reject unsupported jobs at plan time whenever an `ios-linux` runner exists.** Rejected:
  planning happens before a runner is chosen; narrowing to `ios-sign` lets the job wait for a
  Mac instead.

## Success Criteria

```success-criteria
GOAL: A release workflow with iOS runs end to end on a Linux engine and a Linux `ios-linux` runner, with no Mac in the loop for setup or any step, for apps inside the supported subset, while Mac-only setups behave exactly as before.

SUCCESS CRITERIA:
- A real app built, signed and uploaded on Linux reaches VALID and installs from TestFlight (Phase 0 gate) | verify: manual 1. Run the Phase 0 spike. 2. Record the build number, receipt and omarchy-apple-dev commit in this plan.
- `upload.appStore` with an `asc_key` uploads through the API from a Linux engine, and reports rejections and timeouts | verify: tool/e2e/release_e2e.sh prod
- A configured runner reports `ios-linux` after a service restart, and each missing piece as a reason with a fix | verify: (cd packages/xp_engine && dart test test/src/runners/runner_probe_test.dart) && (cd apps/xp && dart test test/src/runner)
- A `build.ios` job runs on a Linux runner through stubbed omarchy-apple-dev scripts and produces the IPA and dSYMs | verify: tool/e2e/runner_ios_linux_e2e.sh
- Each unsupported case (flavor, Shorebird iOS, debug, profile, extension, Simulator target) narrows to `ios-sign` at plan time with its reason, never mid-build | verify: (cd packages/xp_engine && dart test test/src/scheduler test/src/dispatch)
- With only a Mac runner, existing workflows behave unchanged | verify: tool/e2e/release_e2e.sh dev && tool/e2e/release_e2e.sh prod
- The built-in `prod-release`, unchanged, runs end to end with a Linux engine and a Linux `ios-linux` runner on a test app hosted on GitHub with no Flutter flavor, no Shorebird and no extensions: Android and iOS built and uploaded, dSYMs and Dart symbols archived | verify: manual 1. Set up a Linux engine and an ios-linux runner. 2. Dispatch prod-release on the test app. 3. Check both uploads, the archived symbols and VALID in App Store Connect. 4. Record the receipt in this plan.
- No Mac is involved at any point for that app, setup included: triggered and approved remotely with `xp`, signed with a certificate created on Linux | verify: manual 1. Set the app up from a Linux machine only (engine, runner, credentials, certificate via Phase 4b). 2. Dispatch and approve with xp from another machine. 3. Record that no step or setup used a Mac.
- The workspace stays green | verify: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract

NON-GOALS:
- Shorebird iOS on Linux (decided separately).
- The iOS Simulator, macOS apps, the XPath DMG.
- Downloading, bundling or redistributing any Apple SDK.
- Ad hoc and enterprise distribution, Apple ID password uploads.
- Projects on non-GitHub hosts running `prod-release` (the runner plan's R10 refuses them).

VERIFICATION COMMAND: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract && tool/e2e/release_e2e.sh dev && tool/e2e/release_e2e.sh prod && tool/e2e/runner_ios_linux_e2e.sh
```

## Success Metrics

- At least one real app ships to TestFlight from Linux only (Phase 0 and the final manual
  check).
- Zero iOS jobs fail mid-build because of a Linux limitation; every such case is a plan-time
  narrowing with a reason.
- API-key flavors on Macs no longer call altool.

## Dependencies & Prerequisites

- ADR 0014 accepted (Phase 0).
- The runner plan's R1 (probe reasons) and R2 (`xp runner doctor`) before Phase 2; its R4
  (runner URL, and the `docs/guide/runners.md` page) for Phase 5 and an owner without a Mac;
  its R10a's foreign-keys-off migration support for Phase 4a (or 4a adds it).
- The UX plan's U2c dry run, to show narrowing reasons before dispatch (not blocking).
- Upstream #73 for obfuscation and #77 for strip-and-reexport on Linux.
- An Omarchy machine with the toolchain installed, a user-supplied `Xcode.xip`, an Apple
  developer account and a test app.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| omarchy-apple-dev is young and changes under us | XPath pins one commit per release, the probe checks it, and the job records it. |
| A Linux build passes locally but is rejected by App Store processing | Phase 0 gate on a real app; Phase 1 maps API warnings to rejections; the final check is a manual receipt. |
| Using the Xcode SDK on non-Apple hardware is likely outside Apple's SDK agreement | Opt-in only; the user supplies `Xcode.xip`; the docs say licensing is the user's. |
| A job lands on Linux and fails mid-build | `build.ios` accepts `ios-linux` only in Phase 3b, after placement (3a) and signing (4a) exist, and the planner narrows every known unsupported case. |
| The pin drifts after a runner self-update | The probe reports the mismatch with the exact `git checkout` fix; the engine logs the lost capability. |
| Disk fills with per-version Flutter installs (about 7 GB each) | Doctor checks free space; housekeeping frees unused installs. |

## Resource Requirements

One engineer. Phase 1 is M and independent of Linux. Phases 2, 3a, 4a, 3b, 4b and 5 are S or M each. Phase 0 needs a
day on real hardware plus App Store processing time.

## Future Considerations

- Remove each narrowing case as its upstream task lands (flavors first).
- Shorebird iOS on Linux after the decision above.
- An `ios-linux` runner image, once the toolchain can be installed without an interactive
  `Xcode.xip` step.

## Documentation Plan

- ADR 0014 moves to Accepted after Phase 0.
- `docs/guide/runners.md` gains a "Linux iOS" section (Phase 5); `skills/xpath-setup`,
  `skills/xpath-workflows`, `docs/design/PRODUCT.md` and the capability table are updated.
- The runner plan's version rules mention the omarchy-apple-dev pin.

## Related plans

| Topic | Owner | Note |
|---|---|---|
| Probe reasons, `xp runner doctor` | Runner plan (R1, R2) | Phase 2 adds `ios-linux` to them. |
| Foreign-keys-off migrations | Runner plan (R10a) | Phase 4a's credential-kind rebuild reuses it, or adds it if it lands first. |
| `XP_IOS_LINUX_DIR` | **This plan (Phase 2)** | Written into the service unit like the runner plan's R7 `ANDROID_HOME`. |
| Queue and dry-run reasons | UX plan (U1a-1, U2c) | Show this plan's narrowing reasons; if 3a lands after U2c, 3a adds them to the dry run. |
| Step schema capabilities | UX plan (U3b) | Lists `build.ios` as any of `ios-sign`, `ios-linux` once Phase 3a lands. |
| App Store Connect adapter and fake | Shared with UX plan U7a | Phase 1 adds build uploads; U7a adds phased-release routes. |
| Guide page for runners | Runner plan | Phase 5 adds its section to `docs/guide/runners.md`. |
| ADR numbers | — | 0014 is this plan; the runner plan's git-host ADR is 0015. |
| Migration numbers | — | Assigned in merge order across all three plans (last today: v14). |

## References & Research

### Internal References

- [ADR 0014](../adr/0014-ios-builds-on-linux.md); D-09, D-14, D-19, D-20 in
  `docs/plan/2026-10-13-feat-xpath-release-tool-plan.md`; ADR 0012, ADR 0013
- `packages/xp_engine/lib/src/scheduler/scheduler.dart` (`_place`, `_whyNoRunner`)
- `packages/xp_engine/lib/src/steps/build/build_settings.dart:112`
- `apps/xp/lib/src/runner/service/runner_service.dart:45-50`

### External References

- [omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev)
- [App Store Connect API: build uploads](https://developer.apple.com/documentation/appstoreconnectapi)
- [rcodesign](https://gregoryszorc.com/docs/apple-codesign/stable/)

### Related Work

- Upstream PRs #72–#77 in omarchy-apple-dev
- [Runner onboarding plan](2026-10-22-feat-remote-runner-onboarding-plan.md)
- [UX improvements plan](2026-10-22-feat-ux-improvements-plan.md)
