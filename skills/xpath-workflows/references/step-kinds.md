# Step kinds and their `with` keys

From `StepPlanners` (`packages/xp_engine/lib/src/dispatch/step_planners.dart`), the catalogue the
parser checks documents against and `GET /workflows/schema` serves. A key that is not listed is a
validation issue. Everything not under `with` (the worktree, the version, the flavor's ids, the
Flutter pin, the secrets of the flavor's credentials) the engine fills in.

**Engine only** means a job with this step never goes to a remote runner. **Side effect** means
the engine never repeats the step on its own after an interruption: the job waits for an
explicit resume, which asks the step whether its work exists first (`alreadyDone`).

## Source and version

| Kind | `with` keys | Notes |
|---|---|---|
| `git.checkout` | `commitFrom` | First step of every job: makes the job's worktree when the job runs. `commitFrom: <job id>` starts from the version commit that job (an earlier stage, same matrix cell) made. On a runner it fetches the exact commit over the runner's own SSH key. |
| `version.bump` | none | Writes `x.y.z+build` into the pubspec and the flavor's `versionFiles`, and commits `chore(release): x.y.z+build` in the job's worktree. Pushes nothing. A workflow with it gets a build number at dispatch. Side effect. |
| `guard` | `checks`, `credentialKinds` | Runs the listed checks: `source`, `appStoreTrain`, `versionSync`, `patchTarget`, `newReleaseNumber`, `patchNativeDiff`, `playTargetSdk`, `buildNumberReuse`, `credentials`. `credentialKinds` narrows the `credentials` check to the kinds the job needs. Engine only. |

## Build

| Kind | `with` keys | Notes |
|---|---|---|
| `build.android` | `artifact` (`apk` default, or `aab`), `dartDefineFile`, `obfuscate`, `keystore` | `flutter build apk|appbundle --release` with the app's pinned Flutter. The flavor's `keystore` credential reaches the build as `XPATH_KEYSTORE_FILE`, `XPATH_KEYSTORE_STORE_PASSWORD` and `XPATH_KEYSTORE_KEY_PASSWORD` unless `keystore: false`. Needs `android`, `flutter`. |
| `build.ios` | `exportOptionsPlist` (required), `dartDefineFile`, `obfuscate` | On a Mac, `flutter build ipa --release`; on a Linux runner set up for it, omarchy-apple-dev's `flutter/build.sh` and `flutter/ship.sh`, signed with the flavor's Apple Distribution identity and a profile the engine makes (ADR 0014). Needs `flutter` and `ios-sign` or `ios-linux`; the planner narrows to `ios-sign` what Linux cannot build. |
| `build.verifyCompiledConfig` | `artifactName`, `dartDefineFile`, `keys`, `needles` | Reads the AOT snapshot of a stored package and fails if a literal `needles` string or the value of a `keys` entry of the dart-define file (a URL is reduced to its host) is missing. |
| `ios.stripAndReexport` | `frameworks`, `exportOptionsPlist` (required), `dartDefineFile` | Deletes the named frameworks from the archive, re-exports with `xcodebuild -exportArchive` and stores the new IPA over the old one. Needs `ios-sign`: a job with it goes to a Mac. |
| `symbols.archive` | `android`, `ios`, `debugInfoDirectory`, `dartDefineFile`, `obfuscate` | Keeps the R8 `mapping.txt`, the zipped dSYMs and the obfuscation debug info as artifacts. A missing symbol is a warning. `android` and `ios` default to the job's platform. |
| `record.manifest` | `dartDefineFile` | Stores `manifest.json`: version, build, tag, commits, dirty flag, flavors, tool versions, hashes of `pubspec.lock` and the dart-define file, and every artifact with its SHA-256. Needs a build number. |

`dartDefineFile` is relative to the app. `obfuscate: true` adds `--obfuscate --split-debug-info`.

## Shorebird

| Kind | `with` keys | Notes |
|---|---|---|
| `shorebird.release` | `platform`, `artifact` (`aab` default, or `apk`), `exportOptionsPlist`, `dartDefineFile`, `obfuscate`, `keystore`, `shorebirdAppId` | `shorebird release android|ios` with the pinned Flutter. `platform` defaults to the job's; `shorebirdAppId` to the flavor's. The `shorebird` credential's key goes in `SHOREBIRD_TOKEN`. Needs `flutter` and the platform's capability. May run on a runner. Side effect. |
| `shorebird.patch` | `platform`, `exportOptionsPlist`, `dartDefineFile`, `obfuscate`, `allowNativeDiffs`, `shorebirdAppId` | `shorebird patch android|ios --release-version=<releaseVersion>` with the Flutter of that release. The dispatch must give `releaseVersion`. Side effect. |

## Tests

| Kind | `with` keys | Notes |
|---|---|---|
| `test` | `paths`, `tags` | `flutter test --machine`; fails only on failures that are new against the baseline (the last green run on the base branch). Needs `flutter`. Engine only. |
| `analyze` | `failOn` (`error` default, `warning`, `info`) | `flutter pub get`, then `flutter analyze`; fails on an issue of `failOn` severity or worse. Needs `flutter`. |

## Upload (all engine only, all side effects)

| Kind | `with` keys | Notes |
|---|---|---|
| `upload.firebase` | `appId` (required), `artifactName`, `artifactsFrom`, `testerEmails`, `groupAliases`, `releaseNotes` | Firebase App Distribution with the flavor's `firebase_sa` credential. `appId` is the Firebase app id (`1:123456789012:android:...`). Takes the APK by default. |
| `upload.play` | `artifactName`, `artifactsFrom`, `packageName`, `track`, `status`, `userFraction`, `releaseName`, `releaseNotes` | Google Play with the flavor's `play_sa` credential. `packageName` defaults to the flavor's Android application id; `track` to `internal`; `status` is `completed` (default), `inProgress` (with a `userFraction` between 0 and 1) or `draft`. `releaseNotes` maps a language tag to text. Takes the AAB by default. Never cancels a review in progress. |
| `upload.appStore` | `appleAppId` (required), `artifactName`, `artifactsFrom`, `bundleId` | With the flavor's `asc_key`, uploads through the App Store Connect build-upload API on any engine; with an `apple_id`, runs `xcrun altool --upload-package` and needs `ios-sign`. `bundleId` defaults to the flavor's iOS bundle id. |

`artifactsFrom: <job id>` takes the file from the job of the same matrix cell in an earlier
stage (the build job), which is how an upload runs on the engine while the build ran on a runner.

## Git and GitHub (all engine only, all side effects)

| Kind | `with` keys | Notes |
|---|---|---|
| `git.releaseBranch` | none | Cuts `release/<x.y.z>` (by the project's release model) at the head of the worktree; never forces. Needs a bumped version. |
| `git.tag` | none | Tags `v<x.y.z>+<build>`, or `-p<n>` for a patch. An existing tag on the same commit is reused; one on another commit fails. |
| `git.push` | `branch`, `tag` | Pushes the release branch and the tag. `branch` defaults to true when the run bumps a version; `tag` to true. |
| `github.createPr` | `title`, `body` | Opens the release pull request from the release branch to the base branch, or reuses an open one. |
| `github.mergePr` | none | Merges the release's pull request with a merge commit, only when the release is `live` and only the tagged commit. Needs a run with `release` (started by `POST /releases/{id}/merge`). |
| `shorebird.track` | `patchNumber` (required), `action` (`promote` or `rollback`), `shorebirdAppId` | Engine only. Promotes a Shorebird patch of the dispatched `releaseVersion` to the stable track, or rolls it back, with the flavor's Shorebird key. Needs a run with `release` (started by `POST /releases/{id}/patches/{number}/{action}`). |
| `store.rollout` | `store` (`apple` or `play`), `action`, `userFraction` | Engine only. Apple's phased release: `pause`, `resume` or `complete`. Google Play's staged rollout of the release's track: `fraction` (with `userFraction` above 0, at most 1), `halt` or `complete`. Uses the store credential of the release's flavor. Needs a run with `release` (started by `POST /releases/{id}/rollout`). |

## Command

| Kind | `with` keys | Notes |
|---|---|---|
| `command` | `executable` (required), `arguments`, `workingDirectory`, `environment`, `passThroughEnvironment`, `secretEnvironment`, `secretFiles`, `sideEffect` | Runs a program the owner declares. `workingDirectory` is a folder inside the app (no absolute path, no `..`). `environment` sets variables; `passThroughEnvironment` lists engine variables to pass on; `secretEnvironment` maps a variable to a secret key and `secretFiles` a variable to the path of a 0600 file holding a secret: secrets never go in `arguments`. `sideEffect: true` if it changes anything outside the worktree. |

## Gate

`gate` is not written as a step: `gate: <action>` on a step puts a gate step in front of it.
Actions: `prod_release`, `prod_patch`, `store_submission`, `push`, `merge`, `rollout`, `delete`. Engine only.
`store.rollout` must carry `gate: rollout` and `shorebird.track` `gate: prod_patch`: a workflow
without them is invalid.
