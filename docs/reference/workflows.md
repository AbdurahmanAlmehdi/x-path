# Workflows and the scheduler

The workflow document, the built-in workflows, dispatch and the scheduler. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## Workflows and the scheduler

Phase 11 puts the steps in order and decides when they run (D-11, D-13, D-19). A **workflow** is a YAML
document; **dispatching** it makes a **run**, whose **jobs** wait in the database until the **scheduler**
starts them. The engine is also the local runner; remote runners are described under Runners.

### The workflow document (schema 1)

```yaml
schema: 1                      # required
name: Dev build                # optional
description: ...               # optional
lock: project                  # optional: one run of this workflow at a time per project
inputs:                        # optional: variables a dispatch can set
  notes: {description: Release notes, default: ""}
stages:                        # required; run in order
  - name: build
    jobs:                      # run in parallel, as slots allow
      build:                   # the job id, unique in the workflow
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:                # one job per cell
          platform: ${{ platforms }}     # or [android, ios]
          flavor: ${{ flavors }}
        if: platform == 'android'        # a cell without a job when false
        capabilities: [flutter]          # on top of what the steps need
        steps:
          - kind: build.android          # a step type
            with: {artifact: apk}        # what the step type takes
            if: "!flavor.shorebird"      # the step is left out when false
            gate: prod_release           # the owner approves first (D-13)
```

- **Validation** (`POST /projects/{id}/workflows/validate`, and on every save) uses the `yaml` package's
  spans, so each problem has the line and column where it is: an unknown key (with the allowed ones), a
  value of the wrong type, an unknown step type, an unknown `with` key for that type, an unknown
  capability or gate, a matrix axis that is not `platform` or `flavor`, a platform that is not `android`
  or `ios`, a job id used twice, `commitFrom` or `artifactsFrom` naming a job that is not in an earlier stage, an expression
  that does not parse (the column points into it), or a variable it reads that does not exist there. A
  document with issues is never saved (`422 workflow_invalid`). YAML reads a leading `!` as a tag, so
  quote `"!flavor.prod"`.
- **Expressions** (`if:` and `${{ ... }}` in `name`, matrix values and `with`) are a small language that
  reads values and runs nothing: literals (`'x'`, `"x"`, numbers, `true`, `false`, `null`), variables,
  `a.b` and `a['b']` and `a[0]`, `==`, `!=`, `!`, `&&`, `||` and parentheses. Reading what is not there gives
  `null`, also past a `null`. `&&` and `||` give one of their operands, so `a && b || c` picks a value;
  `null`, `false`, `0` and `''` are false. A string that is one `${{ }}` keeps the type of its value; with
  text around it, it becomes text. There is no function, assignment, loop or `eval`.
- **Variables.** From the dispatch: `app` (`name`, `path`, `hasIos`, `hasAndroid`, `version`), `project`
  (`id`, `fullName`, `baseBranch`), `ref`, `sha`, `version` (the version released, `x.y.z`), `build` (the
  number allocated at dispatch), `bump`, `releaseVersion` and `patch` (for a patch), `platforms`, `flavors`
  and `inputs` (the defaults of the document, then what the request gave). A matrix adds `platform` and
  `flavor` (`name`, `prod`, `shorebird`, `implicit`, `entrypoint`, `iosBundleId`, `androidAppId`,
  `shorebirdAppId`, and `credentials.<kind>` for each credential the flavor has, such as
  `flavor.credentials.play_sa`). `if` is evaluated when the workflow is dispatched, not while the job runs.
- **Steps** are the registered step types; the engine fills in what it knows (the worktree, the commit, the
  version and build number, the flavor and its ids, the Flutter pin, the secrets of the flavor's
  credentials), so `with` carries only what varies. `StepPlanners` has the table: `command`,
  `git.checkout`, `guard`, `version.bump`, `build.android`, `build.ios`, `build.verifyCompiledConfig`,
  `ios.stripAndReexport`, `shorebird.release`, `shorebird.patch`, `symbols.archive`, `record.manifest`,
  `test`, `analyze`, `upload.appStore`, `upload.play`, `upload.firebase`, `git.releaseBranch`, `git.tag`,
  `git.push`, `github.createPr` and `github.mergePr`. The inputs are the ones of the sections above; a workflow gets the credentials by
  flavor and kind (`upload.firebase` needs a `firebase_sa` credential, `upload.play` a `play_sa`,
  `upload.appStore` an `asc_key` or `apple_id`, Shorebird steps a `shorebird` key if there is one). The
  Android keystore of a `keystore` credential reaches a build as `XPATH_KEYSTORE_FILE` (a 0600 file),
  `XPATH_KEYSTORE_STORE_PASSWORD` and `XPATH_KEYSTORE_KEY_PASSWORD`. The Firebase app id of a flavor is
  an input (`firebaseAppIds: {dev: {android: "1:..."}}`), as are the App Store Connect app ids.
- **`git.checkout`** is the first step of every job. It makes the job's worktree when the job runs, not at
  dispatch, so a queued job holds no directory; with `commitFrom: <job id>` it starts from the version
  commit that an earlier job of the run made (`version.bump`), so every platform of a release builds
  the very commit that is tagged. `git.releaseBranch` cuts `release/<x.y.z>` at the head of the worktree,
  `git.tag` tags it (`v<x.y.z>+<build>`, or `-p<n>` for a patch; an existing tag on the same commit is
  reused, one on another commit fails, nothing is forced) and `git.push` pushes the branch and the tag.
  Worktrees of finished jobs are kept for resume and inspection until the housekeeping of Phase 12c.
  On a remote runner `git.checkout` is the runner's own step (see Runners): the commit comes from GitHub over
  the runner's SSH key.
- **`artifactsFrom: <job id>`** under `with` of `upload.play`, `upload.firebase` and `upload.appStore` takes the
  file to upload from a job of an earlier stage (the build job) instead of from the job the step is in. The
  planner stores the id of the job of the same matrix cell as `artifactJob` in the step input; a step
  without it looks in its own job. This is how an upload can run on the engine while the build ran on a
  runner, which uploaded what it built to the engine's artifact store (ADR 0010).
- **Gates** (D-13). `gate: prod_release | prod_patch | store_submission | push | merge | rollout | delete` on a step
  puts a `gate` step in front of it. The gate asks the `ApprovalGate` port (`xp_engine`) about the action,
  project, commit and version, and while nobody decided, its step returns `StepWaiting`: the job stops in
  state **`waiting_for_approval`**, holding no slot and no runner, and its run holds the project lock.
  Whoever decides a gate calls `Scheduler.resumeWaiting(projectId:)`; each waiting job asks again and goes
  on (approved), fails (denied or expired) or waits again. The `ApprovalService` (Phase 12a) is the gate: only
  `app` and `cli` tokens decide (`/approvals`), and the engine never approves on its own. A production release
  therefore stops at its first gate until the owner approves; a dev build or test run is not affected.
- **Matrix.** `platform` takes `android` and `ios`, `flavor` a flavor name; the values are written out or
  come from `${{ platforms }}` / `${{ flavors }}` (or an input). A job is made for each cell whose `if` is
  true. The default platforms are what the app has; the default flavors are the production flavors for a
  workflow with `lock: project` and the others otherwise (an app with one flavor always uses it).
- **Capabilities.** A job needs what it declares plus what its steps imply: `android` and `flutter` for
  `build.android`, `ios-sign` and `flutter` for `build.ios`, `ios-sign` for `upload.appStore` with an Apple
  ID (nothing with an API key), the platform's for Shorebird steps, `flutter` for `test` and `analyze`. A
  need can be any of several capabilities, written `ios-sign|ios-linux` in the job's `capabilities`, the
  first preferred. `build.ios` and `ios.stripAndReexport` need any of `ios-sign` and `ios-linux` (ADR 0014),
  and the planner narrows a job Linux cannot build to `ios-sign` with the reasons (`iosLinuxLimits`): the
  owner turned Linux iOS builds off for the app, Shorebird iOS, a debug or profile build, an app
  extension, the iOS Simulator, the strip step, a flavor without an Apple Distribution identity and an ASC
  key, and what the scan found (`AppProfile.iosLinuxLimits`: plugins that build with CocoaPods, a Run
  Script phase beyond Flutter's own, a Flutter older than 3.47; `FlavorProfile.iosLinuxLimits`: a
  multi-size app icon set, an `INFOPLIST_FILE` other than `Runner/Info.plist`, an icon set outside
  `Runner/Assets.xcassets`). Flavors and entry points build on Linux. The queue message and the dry run
  repeat them; with no paired runner that offers `ios-sign` the dispatch fails. A workflow cannot name `ios-linux`.

### Built-in workflows and versions

Every project gets `dev-build`, `prod-release`, `release-merge`, `release-rollout`, `shorebird-patch`, `shorebird-track`, `smoke-build` and `test` the first time its workflows
are listed (and a new version of one when the engine ships another document). They compose the steps in the
order of `ship.sh`. **The job that builds has no step only the engine may run** (ADR 0010), so that it can be
leased to a runner: the guards, the gates, the uploads, the tag and the pushes are in engine jobs of an earlier
or later stage, and the uploads take what the runner built from the engine's artifact store (`artifactsFrom`).

| Workflow | Stages | Notes |
|---|---|---|
| `dev-build` | `check`, `build`, `upload` (each: platform x flavor) | No lock: as many as the slots allow. `check` (engine): `git.checkout`, `guard` source and credentials. `build` (runner-eligible): `git.checkout`, `version.bump` (a dev build pushes nothing, so the version commit stays in the job's worktree), `build.android` / `build.ios`, `record.manifest`. `upload` (engine, only for a platform and flavor that has something to upload): `upload.firebase` (an Android build with an app id in `firebaseAppIds`) or `upload.appStore` (an iOS build with an id in `appleAppIds`). |
| `prod-release` | `prepare`, `check`, `build`, `upload`, `finalize` | `lock: project`. `prepare` (engine) bumps the version once, cuts the release branch after `gate: prod_release` and pushes the branch after `gate: push`, so that a runner can fetch the version commit (ADR 0009). `check` (engine): `versionSync`, `buildNumberReuse`, `credentials`, and the store checks, from that commit. `build` (runner-eligible): `git.checkout` from that commit, `shorebird.release` (a Shorebird flavor) or `build.android` / `build.ios`, `symbols.archive`, `record.manifest`. `upload` (engine): `upload.play`, `upload.firebase`, `upload.appStore`, the ones the flavor has credentials for. `finalize` (engine) tags, pushes the tag and opens the release pull request (`github.createPr`). The approval of the push covers the tag push too (it binds to the same project, commit, version and run). A run of it is a release (see Releases). |
| `release-merge` | `merge` | Merges the pull request of a release: `gate: merge`, then `github.mergePr`. Started by `POST /releases/{id}/merge`, no project lock. |
| `release-rollout` | `rollout` | Changes the rollout of a release in a store: `gate: rollout`, then `store.rollout` (engine only). Inputs `store`, `action` and `userFraction`. Started by `POST /releases/{id}/rollout`, no project lock. |
| `shorebird-patch` | `check`, `patch` (platform x flavor), `finalize` | `lock: project`. Dispatch it with `releaseVersion` (`x.y.z+build`, never `latest`). `check` (engine): the guards, and `gate: prod_patch` in front of the last of them (so that the owner is asked only about a patch that passed the others). `patch` (runner-eligible): `git.checkout`, `shorebird.patch`. `finalize` (engine): the patch tag `v<x.y.z>+<build>-p<n>` and `gate: push`. |
| `shorebird-track` | `track` (each Shorebird flavor) | Promotes a Shorebird patch of a release to the stable track or rolls it back: `gate: prod_patch`, then `shorebird.track` (engine only, `shorebird patches promote` or `rollback`). Inputs `patchNumber` and `action`. Started by `POST /releases/{id}/patches/{number}/{promote\|rollback}`, no project lock. |
| `smoke-build` | `build` (each flavor) | `git.checkout`, then `build.android` with `keystore: false`: an APK signed with the debug key, from the pubspec version. No credential, no store id, no upload, no build number. The app offers it after the first scan, for a green build before signing is set up. |
| `test` | `test` | `test` and `analyze`; allocates no build number. |

Built-ins cannot be edited or deleted (`409`); copy the YAML into a workflow of your own. **Every save is a
new `workflow_version`**, and a dispatch records the exact version it ran: `Job.workflowVersionId` and
`GET .../workflows/{id}?version=n` show what a job ran, even after the workflow changed. A workflow that jobs
ran cannot be deleted.

### Dispatch

`POST /projects/{id}/workflows/{workflowId}/dispatch` takes `ref` (default: the base branch), `app`,
`flavors`, `platforms`, `bump` (`major`, `minor`, `patch`, `keep`) or `version`, `releaseVersion` and
`inputs`. It fetches the mirror, resolves the ref to a commit, reads the version of the app at that commit,
**allocates the build number once for the run** (D-11: `BuildNumberAllocator` over the stores, the tags and
the counter, only for a workflow with `version.bump`; the number is never handed back, even if the run fails),
expands the matrix, plans every step of every job, and only then stores the run and its jobs, all `queued`.
A request that cannot be done (an unknown flavor, a credential a step needs, a value a step refuses) is
`422 workflow_invalid` with the line of the workflow and nothing stored. The answer is `202` with the
`Run` (`GET /runs/{id}` shows it again; its state is derived from its jobs), and `run.dispatched` goes on
`/events`.

| Route | What it does |
|---|---|
| `GET /projects/{id}/workflows` | The workflows of the project, built-ins first made if needed. |
| `POST /projects/{id}/workflows` | `{"name", "yaml"}`: a new workflow at version 1. `409` for a used name, `422` for issues. |
| `POST /projects/{id}/workflows/validate` | `{"yaml"}`: always `200`, with `valid` and the `issues` (`line`, `column`, `message`). |
| `GET /projects/{id}/workflows/{workflowId}[?version=n]` | The workflow with the YAML of a version and the list of versions. |
| `PUT /projects/{id}/workflows/{workflowId}` | `{"yaml"}`: a new version. |
| `DELETE /projects/{id}/workflows/{workflowId}` | Deletes a workflow of your own that no job ran. |
| `POST /projects/{id}/workflows/{workflowId}/dispatch` | Described above. |
| `GET /runs/{id}`, `POST /runs/{id}/cancel` | A run with its jobs; cancel every job that has not ended. |

### The scheduler

`Scheduler` (`packages/xp_engine/lib/src/scheduler`) reads the open runs from the database and, each time
something changes (a dispatch, a job that ends or is cancelled or resumed, a gate decided, the engine
starting), makes one pass that starts what may start. It keeps no state of its own, so a restart loses
nothing, and the same state always gives the same pass.

- **Stages.** A stage starts when every job of the stages before it succeeded. A failed or cancelled job
  holds the later stages (and its queued siblings) back, `queued`, with the reason in the job's `message`,
  until it is resumed and succeeds.
- **The project lock** (D-11). A run of a `lock: project` workflow takes the project when the scheduler
  starts its first job and keeps it, through its stages and through a gate that waits, until it succeeds,
  fails or is cancelled. A second prod release or patch of the project stays `queued` ("Waiting for run
  `<id>` to finish ...") and takes its turn in the order the runs were dispatched; a later run never
  overtakes an earlier one that waits. A run whose failed job is resumed asks for the project again, so it
  waits for a run that took it meanwhile. Dev builds, tests and other projects are not held.
- **Slots and `ios-sign`** (D-19). A runner runs at most `slots` jobs at once: `xpd serve --slots <n>`, by
  default a quarter of the processor cores and at least one. A job that needs `ios-sign` runs alone on its
  machine in that respect (another Mac takes the next). Runs are served oldest first, their jobs by stage
  and creation order; a job that cannot start does not hold up those behind it.
- **Capabilities.** The engine probes this machine (`LocalCapabilities`): `flutter` when `git` runs (the
  pinned SDK is fetched on demand), `android` when an Android SDK is found (`ANDROID_HOME`,
  `ANDROID_SDK_ROOT`, the default places of Android Studio), `ios-sign` when `xcode-select` and
  `xcodebuild` find an Xcode, `swift-linux` when Linux has `swift`. A job goes to a runner that meets
  every need, preferring the runner that meets an any-of need with its first capability (a Mac before a
  Linux runner); if none does the job says "No runner can do ios-sign." and waits. `xpd serve` prints what it
  found. The `SchedulerRunner` interface (`id`, `capabilities`, `slots`, `accepts`, `launch`, `whenFinished`) is
  what the engine (`LocalRunner`) and the remote runners (`RemoteRunner`, see Runners) implement.
- **Placement.** The engine is preferred: a job that fits it and finds a free slot there runs there. A remote
  runner takes what the engine cannot do or has no slot for; among remote runners the least loaded goes first
  (running jobs per slot), then the one that connected first. A runner can refuse a job by its steps
  (`accepts`): a remote runner never gets a job with a step only the engine runs, and a job that waits for that
  says which steps.
- **Resume and cancel** go through the scheduler (`POST /jobs/{id}/resume` puts a dispatched job back in
  the queue and answers with it, `queued` or `running`; a job that is not part of a run resumes at once).

### End to end

`tool/e2e/release_e2e.sh dev` builds the `xpd` bundle and runs `apps/xpd/tool/release_e2e.dart`, which starts
a fake Firebase App Distribution and a fake GitHub, starts `xpd serve` with `XPD_TEST_GITHUB_API_URL`,
`XPD_TEST_FIREBASE_URL` and `XPD_TEST_FILE_SECRETS=1` (**test only**: they point the engine at the fakes and
keep its secrets in a file instead of the Keychain; `xpd` warns when one is set), adds the fixture app as a
project over HTTP, saves a Firebase service account, dispatches `dev-build` for Android (a check, a build and
an upload job), and checks the APK and the manifest of the build job, that the build job has no engine-only
step, and the Firebase release made by the upload job. It then dispatches `prod-release` twice and checks that the second
queues behind the first, which stops at its gate, and runs once the first is cancelled. It needs the
Android SDK, takes a few minutes the first time and is not part of CI (Gradle and the SDK make it too slow
for the Linux workflow).

`tool/e2e/release_e2e.sh prod` runs a whole production release (see Releases) from `draft` to `merged`, over
HTTP only, as an app would: it starts fake App Store Connect (an API key) and iTunes lookup, Google Play,
Firebase and GitHub (`XPD_TEST_ASC_URL` and `XPD_TEST_PLAY_URL` join the variables above; the fake GitHub
knows pull requests and makes a real merge commit in the bare repository that is the fixture's `origin`),
saves the credentials, dispatches `prod-release` for Android and iOS and approves each gate with an app token
(`prod_release`, `push`), then moves the fake stores from review to approved to live, asks for the merge,
checks that an `mcp` token cannot approve it, approves it and waits for `merged`. It checks:

- the states in order (the `release.state_changed` events too), the build number after the highest the fake
  stores have seen, and the tag `v<x.y.z>+<build>` on the tip of the release branch in the origin, reachable
  from the base branch after the merge, which GitHub was asked to do with `merge_method: merge`;
- that Play got one commit with `changesInReviewBehavior=ERROR_IF_IN_REVIEW`, and Firebase none (the fixture's
  prod flavor is not a Shorebird flavor);
- that the owner's folder is unchanged: `git status --ignored`, `HEAD`, every ref and the SHA-256 of every
  file of the working tree before and after;
- that no secret (the GitHub token, the device token, the private keys of the fake ASC key and Play service
  account, whole and line by line) is in a stored log, the SQLite database with its WAL, the engine's output,
  what is left of the engine's temporary folder, or **the arguments of any process the engine started**. Those
  are captured by shims first on the engine's `PATH`: every process a step starts goes through the `perl`
  trampoline of ADR 0003, so the `perl` shim sees the full command line of all of them, and a `git` shim sees
  every git call. They append to `argv.log` and run the real program.

What is real: the engine, its database, mirror, worktrees, tag and push, a real Android App Bundle built by
Gradle, its upload to the fake Play, the polling and the merge. What is faked, because the machine has no signing
identity and Apple has no fake: `flutter build ipa` (an SDK wrapper in the engine's toolchain cache runs the real
Flutter for everything else and writes a placeholder IPA) and `xcrun altool` (a shim prints what a successful
upload prints). It needs macOS with Xcode, since the engine schedules the iOS job where `ios-sign` is, and the
Android SDK; it takes several minutes and is not part of CI.

`tool/e2e/mcp_gate_e2e.sh` (Phase 13, see `xp mcp`) builds the `xpd` and `xp` bundles and runs the same script with
`--mode mcp`. It needs no Android SDK or Xcode: `prod-release` reaches its first gate before any build. It takes about
half a minute.

`tool/e2e/runner_loss_e2e.sh` (Phase 14b, see Runners) runs the same script with `--mode runner-loss`. It needs no
Android SDK or Xcode and takes about four minutes, most of it the production lease of 90 seconds.

`tool/e2e/runner_build_e2e.sh` runs it with `--mode runner-build`: an engine that cannot build Android and a runner that
can. The build job of `dev-build` goes to the runner (its own checkout, a real APK), the check and the upload (to a
local fake Firebase) stay on the engine, and the APK in the engine store is the one the runner built.

`tool/e2e/runner_any_host_e2e.sh` (ADR 0015) runs it with `--mode runner-any-host`: the same build for a project whose
origin is a `file://` bare repository, on an engine with no GitHub token. The engine adds it without GitHub, the
runner fetches the commit from the URL of the lease into a cache named by the source key, and `prod-release` is
refused at dispatch with the host and its `git.push` step.

`tool/e2e/runner_ios_linux_e2e.sh` (ADR 0014, Linux only) runs it with `--mode runner-ios-linux`: an iOS-only copy of
the fixture built twice on a runner set up for Linux iOS builds, whose omarchy-apple-dev scripts and tools are stubs.
The first job prepares the dedicated Flutter install, the second reuses it; `flutter/ship.sh` signs with the identity
and the App Store profile the engine made with its fake App Store Connect and never sees the API key; the IPA, the
dSYMs and the manifest reach the engine.
