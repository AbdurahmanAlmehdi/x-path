---
title: "feat: iOS builds on Linux runners via omarchy-apple-dev"
type: feat
date: 2026-10-22
---

## feat: iOS builds on Linux runners via omarchy-apple-dev

## Overview

Today every iOS step needs a Mac with Xcode, and because `upload.appStore` needs `ios-sign` and
only runs on the engine, the engine must be a Mac too. This plan lets the whole release
workflow, iOS steps included, run on Linux, using
[omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev) as the Linux iOS
toolchain. It is opt-in and experimental per runner; Macs keep working as they do. The decision
record is [ADR 0014](../adr/0014-ios-builds-on-linux.md).

## Goal

Set up once, then trigger and approve releases remotely on a Linux machine, with no Mac in the
loop: not for a build step, not for setup. A job that needs a Mac part-way through does not meet
the goal. So:

- The plan-time rejections below are a safety net, not the design. For the apps this is for, every
  rejection that applies is a prerequisite to remove upstream before the move, not a step left on a
  Mac.
- Setup needs no Mac either: `Xcode.xip` is downloaded in a browser on any OS, and the Apple
  Distribution certificate is created through the App Store Connect API on Linux (a new one,
  rather than exporting the Mac's from Keychain; Apple limits how many a team has, so check the
  count first).
- Releases are triggered and approved with `xp` (or an agent over `xp mcp`) against the Linux
  engine, reached remotely through TLS as for any remote engine.

## What omarchy-apple-dev provides

omarchy-apple-dev (MIT) builds, signs and uploads iOS apps on Linux with Swift 6.4, xtool,
SwiftBuild, a darwin SDK cut from a user-supplied `Xcode.xip`, rcodesign and the App Store
Connect API. Its Flutter path does not run `flutter build ipa`: it runs `flutter assemble` with a
Linux-hosted `gen_snapshot` and shims, builds Runner and the plugins as one SwiftPM package, and
compiles icons and storyboards with its own `actool` and `ibtool`.

The pieces this plan relies on were contributed upstream for it:

| Upstream PR | What it adds | State |
|---|---|---|
| #72 | `flutter/ship.sh [--upload] <app>`: stamp, sign, validate and upload a `flutter/build.sh` build | Merged |
| #73 | `SPLIT_DEBUG_INFO` and `DART_OBFUSCATION` for `flutter/build.sh` | Open |
| #74 | `build/ios-linux/dSYMs`, one dSYM per image | Merged |
| #75 | `STRIP_FRAMEWORKS` for `flutter/build.sh` | Merged |
| #76 | `ASC_EXPORT_OPTIONS`: an Xcode `ExportOptions.plist` for `asc.py identity` | Merged |
| #77 | Strip refuses frameworks loaded through `@executable_path` / `@loader_path` (owner's fix to #75) | Open |

Interface XPath calls (all scripts exit non-zero on failure; none prints JSON):

```sh
flutter/setup.sh                                   # once per Flutter version (~7 GB, 5-12 min)
BUILD_NAME=… BUILD_NUMBER=… SPLIT_DEBUG_INFO=… DART_OBFUSCATION=true STRIP_FRAMEWORKS="A B" \
  flutter/build.sh <app> KEY=VALUE …               # -> build/ios-linux/Payload/Runner.app, dSYMs/
ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=… ASC_EXPORT_OPTIONS=… ASC_ENTITLEMENTS_PATH=… \
  flutter/ship.sh [--upload] <app>                 # -> build/ios-linux/Runner-store.ipa
```

## What is still not possible on Linux

These stay on a Mac, or are rejected on a Linux runner with a clear reason:

- **Needs Apple hardware or the Apple portal:** the iOS Simulator, Flutter macOS apps and the
  XPath DMG, Instruments, creating the App Store Connect app record, creating a Developer ID
  certificate. Integration tests and screenshots are not offered on iOS in a Linux workflow; they
  run on an Android emulator instead (see "No iOS Simulator in Linux workflows").
- **Not built yet:** Shorebird iOS; debug and profile builds; flavors (build configurations);
  plugins without a `Package.swift` (CocoaPods only); app extensions; entitlements beyond
  Associated Domains, push, Sign in with Apple and best-effort app groups; storyboards beyond
  Flutter's template; multi-size and alternate app icons; ad hoc and enterprise distribution;
  Apple ID password uploads; Flutter older than 3.47 (3.47.6 is the verified version). Flavors,
  extensions, storyboards and icons are delegated upstream; Shorebird iOS has its own track (see
  "Upstream work").
- **Built but not yet run on a real build:** full-mode Flutter upload through `flutter/ship.sh`,
  obfuscation with the Linux `gen_snapshot`, dSYMs from a real SwiftBuild, strip-frameworks on a
  real app, export options against App Store Connect. Full Xcode-SDK mode is tested on
  Arch/Omarchy only.

## Where XPath is Mac-bound today

| Blocker | Where |
|---|---|
| `ios-sign` is probed only on macOS with `xcode-select` and `xcodebuild` | `xp_engine/lib/src/runners/runner_probe.dart`, `scheduler/local_capabilities.dart` |
| Each iOS step fails when `isMacOS` is false | `steps/build/build_ios.dart`, `steps/build/strip_and_reexport.dart`, `steps/upload/upload_app_store.dart`, `steps/build/shorebird_release.dart`, `steps/build/shorebird_patch.dart` |
| Upload is `xcrun altool`; `upload.appStore` needs `ios-sign` and is engine-only | `steps/upload/upload_app_store.dart`, `dispatch/step_planners.dart`, `runners/remote_step_policy.dart` (D-09, D-14) |
| No credential kind for a signing identity; a runner is granted only keystore and Shorebird secrets | `xp_api/lib/src/credential.dart`, `runners/runner_secret_grants.dart` (D-09, ADR 0012) |
| The IPA is read from `build/ios/ipa/*.ipa`; dSYMs from the Xcode archive | `steps/build/build_outputs.dart`, `steps/symbols/symbols_archive.dart` |
| Capabilities are a flat all-of set | `scheduler/capability.dart`, `scheduler/scheduler.dart` (`_place`) |

## Phases

### Phase 0: ADR and a spike on real hardware (no product code)

- [ ] ADR 0014 accepted, including the open decision below.
- [ ] Blocker audit of each app that is to move: flavors, plugins without a `Package.swift`, app
      extensions, entitlements, storyboards, app icons, Shorebird use. The result orders the
      "Upstream work" list; an app moves only when its list is empty.
- [ ] On an Omarchy machine with `install-toolchain.sh` done: a workflow of `command` steps runs
      `flutter/setup.sh`, `flutter/build.sh` and `flutter/ship.sh --upload` on a real app.
- [ ] **Gate:** a build of a real app reaches `VALID` in App Store Connect and installs from
      TestFlight. Record which of the "not built yet" items the app hit. Do not start Phase 3
      before this passes on at least one app.

### Phase 1: App Store upload through the App Store Connect API (no Linux needed)

- [ ] Add the build-upload resources to `http_app_store_connect.dart`: `POST /v1/buildUploads`,
      `POST /v1/buildUploadFiles`, the chunked `PUT`s to the returned operations, `PATCH`
      uploaded, then poll the upload state (omarchy-apple-dev `tools/asc.py upload` is a
      working reference).
- [ ] `upload.appStore` uses the API when the flavor's credential is an `asc_key`; altool stays
      for `apple_id` credentials only. Map API error and warning codes to the existing rejection
      reporting.
- [ ] `upload.appStore` no longer needs `ios-sign`; it stays engine-only (D-09). A Linux or Docker
      engine can then upload iOS builds.
- [ ] Extend `tool/e2e/fake_stores/asc` with the build-upload resources; e2e covers success, a
      rejected build and a timeout.
- Amends D-14.

### Phase 2: the `ios-linux` capability

- [ ] Add `ios-linux` to `capability.dart`. `ios-sign` keeps its meaning (a Mac with Xcode) so
      existing workflow YAML is unchanged; Shorebird iOS keeps requiring it.
- [ ] A runner reports `ios-linux` only when started with `--ios-linux=<omarchy-apple-dev dir>`
      and the probe passes: darwin SDK bundle, `swift`, `rcodesign`, `~/pymobile3-venv/bin/python`,
      `llvm-strip`/`llvm-lipo`/`llvm-otool`, and the omarchy-apple-dev commit (pinned, recorded).
- [ ] `build.ios` and `ios.stripAndReexport` require any of `{ios-sign, ios-linux}`: `StepPlanSpec`
      and `_place` learn an any-of requirement. The one-iOS-job-per-machine rule applies to both.
      With both kinds free, the scheduler prefers a Mac.
- [ ] Error text names the missing piece ("No runner can do ios-sign or ios-linux").
- Amends D-19.

### Phase 3: Linux backends for the iOS build steps

- [ ] `build.ios` picks its backend by host. On Linux it runs `flutter/build.sh`, then
      `flutter/ship.sh` without `--upload`:
  - `--build-name`/`--build-number` → `BUILD_NAME`/`BUILD_NUMBER`;
  - `--dart-define-from-file` → `KEY=VALUE` arguments (JSON and `.env` forms);
  - `--obfuscate --split-debug-info` → `DART_OBFUSCATION=true`, `SPLIT_DEBUG_INFO`;
  - `exportOptionsPlist` → `ASC_EXPORT_OPTIONS`;
  - `ios/Runner/Runner.entitlements`, when present → `ASC_ENTITLEMENTS_PATH`.
- [ ] Outputs: the artifact is `build/ios-linux/Runner-store.ipa`; `symbols.archive` takes
      `build/ios-linux/dSYMs` and the Dart symbols directory.
- [ ] `ios.stripAndReexport` on Linux: `flutter/tools/strip-frameworks.py` on the payload, then
      `flutter/ship.sh` again. Only after upstream #77 is merged and pinned.
- [ ] Rejected at plan time on an `ios-linux` runner, with the reason: `--flavor`, app extensions,
      Shorebird iOS, debug and profile builds, an iOS Simulator target. Each rejection names the
      upstream task that lifts it.
- [ ] The job's toolchain record says "Linux, omarchy-apple-dev `<commit>`" next to Flutter's
      version (`build_toolchain.dart`).
- [ ] Unit tests for the argument mapping; e2e on a Linux runner with stubbed `build.sh` and
      `ship.sh` (as upstream's `tests/flutter-ship/run.sh` stubs its tools).
- Amends D-20.

### Phase 4: signing material on a Linux runner

- [ ] New credential kind for the Apple Distribution identity (`.p12`, or `key.pem` + `cert.der`),
      named and assigned per flavor (ADR 0013), checked against App Store Connect's certificate
      list.
- [ ] Grant it to an `ios-linux` job in its tmpfs secret area, wiped at job end and at runner
      start (D-09, `secrets/secret_area.dart`).
- [ ] Profile creation according to the open decision below.

### Phase 5: scan, doctor and toolchain preparation

- [ ] Scan reports what would stop a Linux iOS build before any job: plugins without a
      `Package.swift`, flavors, non-template storyboards, extensions.
- [ ] Doctor and the runner probe check that the project's Flutter version has the Linux
      `gen_snapshot` (`file` reports ELF). A prepare step runs `flutter/setup.sh` in a Flutter
      install dedicated to that version and caches it, because the script replaces
      `gen_snapshot_arm64` in the install it runs on.
- [ ] Docs: `skills/xpath-setup`, `skills/xpath-workflows`, `docs/design/PRODUCT.md`, the README
      capability table. They say XPath never downloads `Xcode.xip`; the user supplies it.

## Open decision

**Who creates the App Store profile for a Linux build.**

- **(a)** The App Store Connect key goes to the runner for the job, and omarchy-apple-dev's
  `asc.py identity` creates the certificate and profile. Least code; widens D-09, under which ASC
  keys never leave the engine.
- **(b) Recommended.** The engine creates the profile with its own App Store Connect client and
  sends only the identity and the profile to the runner, which signs with rcodesign. The ASC key
  stays on the engine. Needs a small upstream change so `asc.py identity` (or `flutter/ship.sh`)
  takes a given profile.

## No iOS Simulator in Linux workflows

XPath has no Simulator step: `test` runs `flutter test` on the host, which works on Linux.
Integration tests and screenshots that need a device run on an Android emulator; iOS ones are not
offered when the iOS build runs on Linux.

- [ ] Workflow validation refuses an iOS Simulator or iOS device target in a step kind that has
      one (none today; a future integration-test or screenshot step) unless its job declares
      `ios-sign`, with the reason and the Android emulator as the alternative. A `command` step
      that calls `xcrun simctl` itself cannot be detected; the docs say it needs `ios-sign`.
- [ ] Device tests and screenshots, when they are added as step kinds, take an Android emulator
      target and the `android` capability.
- [ ] `skills/xpath-workflows` says so, with an Android emulator example.

## Upstream work

Delegated to omarchy-apple-dev (one feature per PR, as its CONTRIBUTING.md asks). Until each lands,
XPath's scan reports the app as needing a Mac for iOS, and plan time rejects the job on an
`ios-linux` runner with the reason. Each item is done when it is merged upstream, pinned by the
runner, and the matching rejection is removed.

- [ ] **Flavors (build configurations and schemes).** `flutter/build.sh` takes the first
      `PRODUCT_BUNDLE_IDENTIFIER` in the pbxproj. It needs the `Release-<flavor>` configuration and
      its xcconfig (bundle id, display name, `$(...)` settings in Info.plist) and `-dFlavor` for
      `flutter assemble`. XPath then maps `--flavor` to it. The largest blocker for apps with
      flavors.
- [ ] **App extensions** (widgets, share, notification service) in the Flutter path: build each
      target as its own product, embed it under `PlugIns/`, sign it with its own profile.
      `asc.py identity` and the top-level `ship.sh` already handle `PlugIns/*.appex`.
- [ ] **Storyboards beyond Flutter's template.** The Linux `ibtool` stops on a feature it does not
      compile; each missing feature is a change there.
- [ ] **Multi-size and alternate app icons.** A multi-size AppIcon can leave App Store processing
      stuck; alternate icons are dropped. Both are `actool` work.
- [ ] Reading `ios/Runner/Runner.entitlements` by default, and more entitlements than Associated
      Domains, push, Sign in with Apple and app groups.
- [ ] A checker that lists plugins without a `Package.swift`, for the scan.
- [ ] A receipt for a full-mode Flutter TestFlight upload with `flutter/ship.sh`.
- [ ] If the profile decision is (b): `asc.py identity` or `flutter/ship.sh` takes a given profile.

### Shorebird iOS on Linux (to decide)

`shorebird release ios` and `shorebird patch ios` need macOS today: the Shorebird CLI refuses iOS
elsewhere, and a release and its patches are built with Shorebird's own engine and Dart fork, whose
iOS `gen_snapshot` and patch tools are macOS binaries. omarchy-apple-dev solves the same problem for
stock Flutter by building a Linux-hosted `gen_snapshot` from the Dart SDK at Flutter's pinned
revision.

- [ ] Decide between:
  - **A feature request to Shorebird** for Linux-hosted iOS releases and patches, offering the
    omarchy-apple-dev approach and our help. Nothing to maintain; depends on their priorities.
  - **Our own fork** of the Shorebird CLI plus a Linux build of Shorebird's iOS `gen_snapshot` and
    patch tools. Works on our schedule, but has to be rebuilt and checked for every Shorebird and
    Flutter release, and a patch must be byte-compatible with what Shorebird's updater expects.
  - Recommended order: the feature request first; a fork only if it is declined and Linux
    Shorebird iOS is still needed. Check the licences of the CLI and the engine fork first.
- [ ] Until then Shorebird iOS keeps requiring `ios-sign` (a Mac).

## Acceptance

- A `prod-release` workflow, unchanged, runs end to end with a Linux engine and a Linux
  `ios-linux` runner on a real app: Android and iOS built, both uploaded, dSYMs and Dart symbols
  archived, the iOS build `VALID` in App Store Connect.
- No Mac is involved at any point for that app, setup included: triggered and approved remotely
  with `xp`, signed with a certificate created on Linux.
- With only a Mac runner, behaviour is unchanged.
- Jobs that cannot run on Linux fail at plan time with the reason, never mid-build.
