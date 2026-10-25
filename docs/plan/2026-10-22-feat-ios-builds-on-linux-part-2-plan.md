---
title: "feat: iOS on Linux part 2: signing and building on Linux"
type: feat
date: 2026-10-22
---

## feat: iOS builds on Linux runners, part 2: signing and building on Linux

> Part 2 of 2 of the [iOS-on-Linux plan](2026-10-22-feat-ios-builds-on-linux-plan.md), PR 6 of
> 6 across the three plans. The decision record is [ADR 0014](../adr/0014-ios-builds-on-linux.md).
> The parent has the problem statement, what omarchy-apple-dev provides, the upstream work,
> Shorebird iOS and the risks.

A Linux runner signs and builds iOS through omarchy-apple-dev, an owner without a Mac sets up
signing from the CLI, and scan and the dry run say before any job whether an app can build iOS
on Linux.

## Dependencies

- **PR 5 (iOS part 1)** merged.
- **Phase 0 passed** (in the parent plan): a real app built, signed and uploaded on Linux
  reached `VALID` and installed from TestFlight, and ADR 0014 is Accepted. Do not start
  Phase 3b before this.
- **The profile decision below is made** before Phase 4a. Done: (b), in ADR 0014.
- PR 2 (any git host): Phase 4a reuses R10a's foreign-keys-off migration support; if PR 2 has
  not landed, Phase 4a adds it.
- PR 1 (runner core): Phase 5 adds its section to `docs/guide/runners.md`. PR 3 (UX part 1):
  Phase 5's dry-run reasons go into U2c's dry run.
- Upstream omarchy-apple-dev #73 (obfuscation) and #77 (strip) merged and pinned, or those cases
  keep narrowing to `ios-sign`.

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

## Decision: who creates the App Store profile for a Linux build

Decided 2026-10-25, recorded in ADR 0014: **(b)**.

- **(b) Chosen.** The engine creates the profile with its own App Store Connect client and
  sends only the identity and the profile to the runner, which signs with rcodesign. The ASC
  key stays on the engine (D-09 unchanged). Needs a small upstream change so `asc.py identity`
  (or `flutter/ship.sh`) takes a given profile.
- **(a) Rejected.** The App Store Connect key goes to the runner for the job, and
  omarchy-apple-dev's `asc.py identity` creates the certificate and profile. Least code, but it
  widens D-09, under which ASC keys never leave the engine.

## Architecture

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

`/build` runs these phases in order, one per context window, then reviews the whole branch
once and opens one pull request.

### Phase 4a: Signing identity and profile on a Linux runner

- **Status:** Done
- **Scope:** A Linux runner signs with an Apple Distribution identity, and a profile made per
  the engine (decision (b)), that it receives for the job only.
- **Files touched:** `packages/xp_api/lib/src/credential.dart`, `packages/xp_api/openapi.yaml`,
  `packages/xp_adapters/lib/src/sqlite/migrations.dart` and a new snapshot golden (the
  `credential.kind` and `credential_ref.kind` `CHECK` constraints change, so both tables are
  rebuilt with foreign keys off: the runner plan's R10a adds that migration support; if this
  lands first, it adds it),
  `packages/xp_engine/lib/src/runners/runner_secret_grants.dart`,
  `apps/xp/lib/src/runner/secrets/secret_area.dart`,
  `packages/xp_engine/lib/src/stores/apple/**` and
  `packages/xp_adapters/lib/src/stores/apple/http_app_store_connect.dart` (certificate list,
  profile creation), `apps/xpd/test/contract/`, tests
- **Acceptance criteria:** an `ios-linux` job receives the identity and the engine-made
  profile in its tmpfs secret area, and both are gone after the job and after a runner
  restart; an identity whose certificate App Store Connect does not list is refused when
  assigned.
- **Validation:** `melos run test:coverage && melos run test:contract`

- [x] A new credential kind for the Apple Distribution identity (`.p12`, or `key.pem` +
      `cert.der`), named and assigned per flavor (ADR 0013), imported with
      `xp credentials add` or in the app, checked against App Store Connect's certificate list.
      Built as `apple_distribution`: `privateKey` (PEM) and `certificate` (DER or PEM); a
      `.p12` is converted with `openssl pkcs12` (the field help says how), since parsing every
      Keychain export cipher in the engine is not worth it. Migration v20 rebuilds `credential`
      (foreign keys off). The assignment check lists the team's distribution certificates with
      the flavor's ASC key and refuses a serial number it does not find.
- [x] Grant it to an `ios-linux` job in its tmpfs secret area, wiped at job end and at runner
      start (D-09). `build.ios` carries `linuxSigning` (`ASC_SIGNING_KEY`, `ASC_SIGNING_CERT`,
      `ASC_PROFILE` to secret keys), which `RunnerSecretGrants` grants; the runner keeps them
      in its existing secret area.
- [x] The engine creates the App Store profile with its App Store Connect client and grants it
      with the identity; the ASC key never reaches the runner (decision (b)).
      `AppStoreProfiles` makes (or reuses) `XPath <bundle id> <serial>` when the runner asks
      for the profile key.
- [x] Until this lands, a job without an assigned identity narrows to `ios-sign` (a 3a rule).
      The reason names `xp credentials add --kind apple_distribution`.
- [x] Upstream: `flutter/ship.sh` signs with a given identity and profile (`ASC_PROFILE`,
      `asc.py given-identity`, no API call, no certificate made). It is on the fork branch
      `AbdurahmanAlmehdi/omarchy-apple-dev` `xpath/pin` (upstream `955127b` + #81 + #82 + this
      change), which XPath pins until upstream #81 and #82 (and this change) merge; the pin then
      moves to an upstream commit.

### Phase 3b: The Linux build backend and toolchain preparation

- **Status:** Done
- **Scope:** `build.ios` runs on an `ios-linux` runner through omarchy-apple-dev; the runner
  prepares and cleans up a dedicated Flutter install per version. This is the PR that lets
  `build.ios` accept `ios-linux`. Amends D-20.
- **Files touched:**
  `packages/xp_engine/lib/src/steps/build/{build_ios,build_outputs,build_toolchain}.dart`,
  `packages/xp_engine/lib/src/steps/symbols/symbols_archive.dart`,
  `packages/xp_engine/lib/src/dispatch/step_planners.dart` (`build.ios` any-of),
  `apps/xp/lib/src/runner/**` (prepare step), `packages/xp_adapters/lib/src/housekeeping/**`,
  a new `tool/e2e/runner_ios_linux_e2e.sh`, tests
- **Acceptance criteria:** with stubbed `setup.sh`, `build.sh` and `ship.sh`, a `build.ios` job
  runs on a Linux runner and produces `Runner-store.ipa` and dSYMs; the first job for a Flutter
  version prepares a dedicated install and later jobs reuse it; with only a Mac runner,
  behaviour is unchanged.
- **Validation:** `(cd packages/xp_engine && dart test test/src/steps/build test/src/scheduler) && tool/e2e/runner_ios_linux_e2e.sh && tool/e2e/release_e2e.sh prod`

- [x] `build.ios` picks its backend by host. On Linux it runs `flutter/build.sh`, then
      `flutter/ship.sh` without `--upload`:
  - `--build-name`/`--build-number` → `BUILD_NAME`/`BUILD_NUMBER`;
  - `--dart-define-from-file` → `KEY=VALUE` arguments (JSON and `.env` forms);
  - `--obfuscate --split-debug-info` → `DART_OBFUSCATION=true`, `SPLIT_DEBUG_INFO` (after
    upstream #73 is merged and pinned; until then obfuscated builds narrow to `ios-sign`);
  - `exportOptionsPlist` → `ASC_EXPORT_OPTIONS`;
  - `ios/Runner/Runner.entitlements`, when present → `ASC_ENTITLEMENTS_PATH`;
  - the identity and the engine-made profile (4a's `linuxSigning`) → `ASC_SIGNING_KEY`,
    `ASC_SIGNING_CERT`, `ASC_PROFILE` (the pinned fork's given-identity signing).
  - `build.sh` builds `lib/main.dart` only, so a flavor with another entry point narrows
    to `ios-sign` too (a new 3a reason).
- [x] Outputs: the artifact is `build/ios-linux/Runner-store.ipa`; `symbols.archive` takes
      `build/ios-linux/dSYMs` and the Dart symbols directory.
- [x] **Toolchain preparation.** A prepare step runs `flutter/setup.sh` in a Flutter install
      dedicated to that version under `<data dir>/toolchains/flutter-ios-linux/<version>`
      (the script replaces `gen_snapshot_arm64` in the install it runs on), checks that
      `gen_snapshot` is ELF, and caches it. Housekeeping knows these installs and frees the
      ones no recent job used. Built into `build.ios` on Linux: a `FlutterResolver` without
      fvm over `toolchains/flutter-ios-linux`, `IosLinuxToolchain` (ELF check, commit, and
      `markUsed`, which frees installs no job used for 30 days; the runner has no
      housekeeping of its own, so this is it).
- [x] `ios.stripAndReexport` keeps requiring `ios-sign` until upstream #77 is merged and
      pinned; then a small follow-up runs `flutter/tools/strip-frameworks.py` on the payload
      and `flutter/ship.sh` again. #77 is in the pin now; the step narrows its job to
      `ios-sign` with a reason until that follow-up.
- [x] The job's toolchain record says "Linux, omarchy-apple-dev `<commit>`" next to Flutter's
      version (`build_toolchain.dart`).
- [x] Tests: unit tests for the argument mapping; e2e on a Linux runner with stubbed scripts
      (as upstream's `tests/flutter-ship/run.sh` stubs its tools). `runner_ios_linux_e2e.sh`
      is Linux only and was not run while building this (on a Mac); the pin moved to the
      fork's `xpath/pin` (`4e170a0`).

### Phase 4b: Signing set-up without a Mac

- **Status:** Not started
- **Scope:** An owner without a Mac (so without the desktop app) creates the distribution
  certificate from the CLI.
- **Files touched:** `apps/xpd/lib/src/api/credentials/**` (a certificate-creation route),
  `packages/xp_engine/lib/src/stores/apple/**`,
  `packages/xp_adapters/lib/src/stores/apple/http_app_store_connect.dart` (certificates),
  `packages/xp_api/openapi.yaml`, `packages/xp_client/**`, `apps/xpd/test/contract/`,
  `apps/xp/lib/src/commands/credentials_commands.dart`,
  `packages/xp_repositories/lib/src/credentials_repository.dart`,
  `apps/xp_desktop/lib/credentials/**`, `tool/e2e/fake_stores/**` (asc certificates), tests
- **Acceptance criteria:** against the fake store, `xp credentials add --kind
  apple-distribution --create` produces an identity assigned to the flavor; the ASC key never
  leaves the engine.
- **Validation:** `melos run test:coverage && melos run test:contract`

- [ ] The engine makes a key and a CSR and creates the certificate through the App Store
      Connect API with the flavor's ASC key, which stays on the engine (D-09). The CLI and the
      app call that route.
- [ ] Before creating one, the route reads the team's distribution certificates and refuses
      with the count and Apple's limit when the team is at it, naming the ones it could
      revoke.
- [ ] The ASC key and the runner URL (runner plan R4) are already settable from the CLI.

### Phase 5: Scan, dry run and docs

- **Status:** Not started
- **Scope:** Owners learn before any job whether an app can build iOS on Linux, and the docs
  cover the setup.
- **Files touched:** `packages/xp_engine/lib/src/scan/**` (`app_scanner.dart`,
  `ios_files.dart`) and its goldens in `packages/xp_engine/test/scan/goldens`,
  `packages/xp_engine/lib/src/dispatch/workflow_dispatcher.dart` (dry run),
  `docs/guide/runners.md`, `skills/xpath-setup/**`, `skills/xpath-workflows/**`,
  `docs/design/PRODUCT.md`, tests
- **Acceptance criteria:** scanning an app with a CocoaPods-only plugin or Flutter flavors
  reports "needs a Mac for iOS" with the reason; the dry run shows the same narrowing reasons.
- **Validation:** `melos run test:coverage`

- [ ] **Project level (scan and the UX plan's U2c dry run):** plugins without a
      `Package.swift`, Flutter flavors, non-template storyboards, extensions, and whether the
      project's Flutter version is 3.47 or later. These depend on the project, not the machine.
- [ ] Docs: a "Linux iOS" section in `docs/guide/runners.md`, `skills/xpath-setup`,
      `skills/xpath-workflows`, `docs/design/PRODUCT.md` and the capability table. They say
      XPath never downloads `Xcode.xip`; the user supplies it, and Apple SDK licensing
      questions are the user's. They also say that iOS device tests and screenshots are not
      offered on Linux (see below).

## Success Criteria

```success-criteria
GOAL: A release workflow with iOS runs end to end on a Linux engine and a Linux ios-linux runner, with no Mac in the loop for setup or any step, for apps inside the supported subset.

SUCCESS CRITERIA:
- An `ios-linux` job receives the identity (and profile) in its tmpfs secret area, and both are gone after the job and after a runner restart | verify: melos run test:coverage && melos run test:contract
- A `build.ios` job runs on a Linux runner through stubbed omarchy-apple-dev scripts and produces the IPA and dSYMs | verify: tool/e2e/runner_ios_linux_e2e.sh
- `xp credentials add --kind apple-distribution --create` creates a certificate through the engine, and the ASC key never leaves it | verify: melos run test:contract
- Scan reports "needs a Mac for iOS" with the reason for flavors and CocoaPods-only plugins | verify: (cd packages/xp_engine && dart test test/scan)
- With only a Mac runner, existing workflows behave unchanged | verify: tool/e2e/release_e2e.sh dev && tool/e2e/release_e2e.sh prod
- The built-in `prod-release`, unchanged, runs end to end with a Linux engine and runner on a test app with no Flutter flavor, no Shorebird and no extensions, with no Mac involved, setup included | verify: manual 1. Set the app up from Linux only (engine, runner, credentials, certificate via Phase 4b). 2. Dispatch and approve with xp from another machine. 3. Check both uploads, the archived symbols and VALID in App Store Connect. 4. Record the receipt in the parent plan.
- The workspace stays green | verify: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract

NON-GOALS:
- Shorebird iOS on Linux; the iOS Simulator; downloading or redistributing Apple software.

VERIFICATION COMMAND: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract && tool/e2e/runner_ios_linux_e2e.sh && tool/e2e/release_e2e.sh dev && tool/e2e/release_e2e.sh prod
```
