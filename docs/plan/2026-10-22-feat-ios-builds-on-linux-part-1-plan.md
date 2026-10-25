---
title: "feat: iOS on Linux part 1: API uploads and the ios-linux capability"
type: feat
date: 2026-10-22
---

## feat: iOS builds on Linux runners, part 1: API uploads and the ios-linux capability

> Part 1 of 2 of the [iOS-on-Linux plan](2026-10-22-feat-ios-builds-on-linux-plan.md), PR 5 of
> 6 across the three plans. The decision record is [ADR 0014](../adr/0014-ios-builds-on-linux.md).
> The parent has the problem statement, what omarchy-apple-dev provides, the upstream work and
> the risks.

App Store uploads go through the App Store Connect API on any engine, a configured Linux runner
reports `ios-linux` with reasons, and the scheduler learns any-of placement and narrowing. No
iOS job runs on Linux yet, so this PR needs neither the hardware test nor the profile decision.

## Dependencies

- **PR 1 (runner core)** merged: Phase 2 adds `ios-linux` to R1's probe reasons and R2's
  doctor, and writes `XP_IOS_LINUX_DIR` into the service unit like R7's `ANDROID_HOME`.
- PR 4 (UX part 2): U7a and Phase 1 both change the App Store Connect adapter and its fake;
  whichever lands second rebases onto the other.
- PR 3 (UX part 1): if U2c's dry run is already merged, Phase 3a adds its narrowing reasons to
  it (U2c's owner rule).

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

## Open decision: who creates the App Store profile for a Linux build

Decide before Phase 4a (signing comes before the first Linux build).

- **(a)** The App Store Connect key goes to the runner for the job, and omarchy-apple-dev's
  `asc.py identity` creates the certificate and profile. Least code; widens D-09, under which
  ASC keys never leave the engine.
- **(b) Recommended.** The engine creates the profile with its own App Store Connect client and
  sends only the identity and the profile to the runner, which signs with rcodesign. The ASC
  key stays on the engine. Needs a small upstream change so `asc.py identity` (or
  `flutter/ship.sh`) takes a given profile.

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

### Phase 1: App Store upload through the App Store Connect API (no Linux needed)

- **Status:** Done
- **Scope:** `upload.appStore` uploads through the build-upload API when the credential is an
  `asc_key`, on any engine, and no longer needs `ios-sign`. Amends D-14.
- **Files touched:**
  `packages/xp_adapters/lib/src/stores/apple/http_app_store_connect.dart`,
  `packages/xp_engine/lib/src/stores/apple/app_store_connect.dart`,
  `packages/xp_engine/lib/src/steps/upload/upload_app_store.dart`,
  `packages/xp_engine/lib/src/dispatch/step_planners.dart`, `tool/e2e/fake_stores/**` (asc),
  tests
- **Acceptance criteria:** against the fake store, an `asc_key` flavor uploads an IPA from a
  Linux engine; a rejected build and a timeout are reported as today's rejections are;
  `apple_id` flavors still use altool.
- **Validation:** `melos run test:coverage && tool/e2e/release_e2e.sh prod`

- [ ] Add the build-upload resources to `http_app_store_connect.dart`: `POST
      /v1/buildUploads`, `POST /v1/buildUploadFiles`, the chunked `PUT`s to the returned
      operations, `PATCH` uploaded, then poll the upload state (omarchy-apple-dev
      `tools/asc.py upload` is a working reference).
- [ ] `upload.appStore` uses the API when the flavor's credential is an `asc_key`; altool stays
      for `apple_id` credentials only. Map API error and warning codes to the existing
      rejection reporting.
- [ ] `upload.appStore` no longer needs `ios-sign`; it stays engine-only (D-09).
- [ ] Extend `tool/e2e/fake_stores/asc` with the build-upload resources; e2e covers success, a
      rejected build and a timeout. The UX plan's U7a extends the same adapter and fake for
      phased releases; whichever lands second rebases onto the other.

### Phase 2: Report the `ios-linux` capability

- **Status:** Done
- **Scope:** A configured runner reports `ios-linux` with reasons when it is missing. No step
  accepts it yet. Amends D-19.
- **Files touched:** `packages/xp_engine/lib/src/scheduler/capability.dart`,
  `packages/xp_engine/lib/src/runners/{runner_probe,runner_hub}.dart`,
  `packages/xp_api/openapi.yaml` (the `Capability` enum, `Runner.capabilities`, the probe
  result frame), `apps/xpd/test/contract/runners_contract_test.dart`,
  `apps/xp/lib/src/runner/**` (start, doctor, `probe_executor.dart`),
  `apps/xp/lib/src/runner/service/runner_service.dart` (writes `XP_IOS_LINUX_DIR`), tests
- **Acceptance criteria:** a runner started with `XP_IOS_LINUX_DIR` set reports `ios-linux`,
  also after a restart under its service; a wrong pin, a missing SDK bundle or a missing tool
  is printed as a reason with its fix; no job is placed on it.
- **Validation:** `(cd packages/xp_engine && dart test test/src/runners/runner_probe_test.dart) && (cd apps/xp && dart test test/src/runner) && melos run test:contract`

- [ ] Add `ios-linux` to `capability.dart`. `ios-sign` keeps its meaning; Shorebird iOS keeps
      requiring it.
- [ ] `XP_IOS_LINUX_DIR` (see Architecture); `install-service` writes it into the unit.
- [ ] The probe checks: the darwin SDK bundle, `swift`, `rcodesign`,
      `~/pymobile3-venv/bin/python`, `llvm-strip`/`llvm-lipo`/`llvm-otool`, and the
      omarchy-apple-dev commit against the pin. Each failure is a `MissingCapability` with a
      fix.
- [ ] `xp runner doctor` lists the same checks plus free disk space (about 7 GB per Flutter
      version).

### Phase 3a: Any-of placement and narrowing (no behaviour change)

- **Status:** Done
- **Scope:** The scheduler and planner learn any-of requirements and the narrowing rule, while
  `build.ios` still requires only `ios-sign`, so nothing changes for users yet.
- **Files touched:** `packages/xp_engine/lib/src/scheduler/{scheduler,capability}.dart`,
  `packages/xp_engine/lib/src/dispatch/step_planners.dart` (`StepPlanSpec`),
  `packages/xp_api/lib/src/job.dart` (`Job.capabilities` as any-of groups),
  `packages/xp_api/openapi.yaml`, `apps/xpd/test/contract/`, tests
- **Acceptance criteria:** scheduler tests with a synthetic any-of step place on either kind,
  prefer a Mac when both are free, and keep one iOS job per machine; each narrowing case
  (`--flavor`, Shorebird iOS, debug, profile, an extension, a Simulator target) has a
  plan-time test that checks the job waits for or fails without an `ios-sign` runner, with the
  reason; existing workflows plan exactly as before.
- **Validation:** `(cd packages/xp_engine && dart test test/src/scheduler test/src/dispatch) && melos run test:contract`

## Success Criteria

```success-criteria
GOAL: iOS builds upload through the App Store Connect API from any engine, a configured Linux runner reports ios-linux with reasons, and placement understands any-of requirements, with no change for Mac-only setups.

SUCCESS CRITERIA:
- `upload.appStore` with an `asc_key` uploads through the API from a Linux engine, and reports rejections and timeouts | verify: tool/e2e/release_e2e.sh prod
- A runner with `XP_IOS_LINUX_DIR` set reports `ios-linux`, also after a service restart, and each missing piece as a reason with a fix | verify: (cd packages/xp_engine && dart test test/src/runners/runner_probe_test.dart) && (cd apps/xp && dart test test/src/runner)
- Each narrowing case (flavor, Shorebird iOS, debug, profile, extension, Simulator target) narrows to `ios-sign` at plan time with its reason | verify: (cd packages/xp_engine && dart test test/src/scheduler test/src/dispatch)
- With only a Mac runner, existing workflows behave unchanged | verify: tool/e2e/release_e2e.sh dev && tool/e2e/release_e2e.sh prod
- The workspace stays green | verify: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract

NON-GOALS:
- Building or signing iOS on Linux (part 2).

VERIFICATION COMMAND: dart analyze --fatal-infos && dart format --set-exit-if-changed . && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract && tool/e2e/release_e2e.sh dev && tool/e2e/release_e2e.sh prod
```
