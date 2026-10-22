# ADR 0014: iOS builds on Linux runners via omarchy-apple-dev

- **Status:** Proposed
- **Date:** 2026-10-22
- **Phase:** Follow-up to D-09, D-14, D-19 and D-20
- **Plan:** [iOS builds on Linux runners](../plan/2026-10-22-feat-ios-builds-on-linux-plan.md)

## Context

Every iOS step needs a Mac with Xcode. `ios-sign` is probed only on macOS with `xcode-select`
and `xcodebuild` (D-19, D-20), and each iOS step checks `isMacOS` itself. `upload.appStore` runs
`xcrun altool` (D-14), needs `ios-sign` and only runs on the engine (D-09), so the engine must be
a Mac as well: the Docker image cannot ship an iOS build.

[omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev) (MIT) builds, signs and
uploads iOS apps on Linux. Its Flutter path runs `flutter assemble` with a Linux-hosted
`gen_snapshot`, compiles Runner and the plugins with SwiftBuild against a darwin SDK cut from a
user-supplied `Xcode.xip`, signs with rcodesign, and uploads through the App Store Connect
build-upload API. Builds made entirely on Linux have reached `VALID` in App Store Connect. The
signing, obfuscation, dSYM, strip and export-options pieces XPath needs were contributed upstream
(#72 to #76; #73 and #77 open at the time of writing).

It does not cover everything: no simulator, no Shorebird iOS, release builds only, no flavors, no
CocoaPods-only plugins, no app extensions in the Flutter path, and full Xcode-SDK mode is tested
on Arch/Omarchy only. Using the Xcode SDK on non-Apple hardware is likely outside Apple's SDK
agreement.

## Decision

**Linux iOS is an opt-in, experimental runner capability.** A new capability, `ios-linux`, is
reported only by a runner started with `--ios-linux=<omarchy-apple-dev dir>` whose probe finds the
toolchain (darwin SDK bundle, Swift, rcodesign, the pymobile3 python, LLVM binutils) and a pinned
omarchy-apple-dev commit. `ios-sign` keeps meaning a Mac with Xcode; existing workflow YAML is
unchanged.

**The same steps, a backend per host.** `build.ios` and `ios.stripAndReexport` accept either
`ios-sign` or `ios-linux` (the scheduler gains an any-of requirement and prefers a Mac when both are
free). On Linux, `build.ios` runs `flutter/build.sh` then `flutter/ship.sh` without upload, mapping
build name and number, dart defines, obfuscation, the export options plist and the app's
entitlements to that interface. Shorebird iOS keeps requiring `ios-sign`. Flavors, Shorebird iOS,
and debug or profile builds are rejected at plan time on an `ios-linux` runner.

**Uploads use the App Store Connect API.** `upload.appStore` uploads through the build-upload API
whenever the credential is an `asc_key`, on any engine; altool remains for `apple_id` credentials.
It no longer needs `ios-sign`. Uploads stay on the engine (D-09 unchanged on this point).

**No iOS Simulator in Linux workflows.** Integration tests and screenshots run on an Android
emulator; workflow validation refuses an iOS Simulator target in a job that can run on Linux.

**Gaps are closed upstream.** Flavors, app extensions, storyboards beyond Flutter's template and
multi-size or alternate app icons are delegated to omarchy-apple-dev; until each lands, the job is
rejected at plan time on an `ios-linux` runner and the scan says the app needs a Mac for iOS.
Shorebird iOS stays on `ios-sign`; whether to ask Shorebird for Linux support or fork it is decided
separately.

**XPath never fetches Apple software.** The user installs omarchy-apple-dev and supplies
`Xcode.xip`; XPath probes, pins and records the toolchain but does not download, bundle or
redistribute any Apple SDK.

**Open: profile creation.** Either the ASC key reaches the runner for the job and
omarchy-apple-dev creates the profile (widens D-09), or the engine creates the profile and sends
only the distribution identity and the profile (recommended; needs a small upstream change). To be
decided before Phase 4 of the plan.

## Consequences

- A Linux engine (including the Docker image) with a Linux runner can run a whole release
  workflow, Android and iOS, for apps inside the supported subset.
- The API upload also removes the altool dependency for API-key flavors on Macs.
- XPath depends on a young upstream project; the runner pins its commit and the job records it.
- A Flutter version needs omarchy-apple-dev's one-time `flutter/setup.sh` (about 7 GB) in a
  dedicated Flutter install on each Linux runner.
- Support questions about Apple SDK licensing are the user's; the docs say so.

## Proof required before Accepted

Phase 0 of the plan: a real app built, signed and uploaded on Linux reaches `VALID` and installs
from TestFlight.
