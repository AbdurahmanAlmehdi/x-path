# Projects, jobs and builds

Scans, jobs and processes, versions and guards, the toolchain, builds and artifacts, Shorebird, symbols, tests and analyze. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

## Projects and scans

A project is a repository, keyed by its source key (D-05, ADR 0015): the GitHub repository id for a GitHub
project, `h` and 16 hex digits of the SHA-256 of the normalised remote for any other host. The folder you pick
only identifies the repository and seeds the first scan; builds run from the engine's own bare mirror.

**Other git hosts** (Bitbucket, GitLab, any SSH server, a `file://` repository) are added by an SSH URL
(`git@host:path` or `ssh://`) or a `file://` URL. The engine reads them with its own SSH key
(`~/.ssh/id_ed25519.pub` of the user it runs as, with no passphrase: the LaunchAgent has no terminal) and
`GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new'`, so the first
connection records the host key and a changed one fails. Adding proves access with `git ls-remote` and, when it
fails, says where to add the key (an access key on Bitbucket). An HTTPS origin on another host answers `422
ssh_url_required` with the SSH URL of the same repository; add it again with that URL (`sshUrl` with a folder).
Only workflows without a `github.*` or `git.push` step run on such a project (`dev-build`, `test`, or custom ones
like them); the others are refused at dispatch with the reason. Pull requests on other hosts are later work.
All routes need a device token.

| Route | What it does |
|---|---|
| `POST /projects` | Adds a project from `{"path": "/abs/clone"}` (reads its `origin`) or `{"remote": "owner/name"}` (or a GitHub URL, or the SSH or `file://` URL of another host), asks GitHub for a GitHub repository or runs `git ls-remote` for another one, sets up the mirror and scans. `409` if it is a project already; `422 ssh_url_required` (with `sshUrl`) for an HTTPS origin on another host. |
| `GET /projects`, `GET /projects/{id}` | The projects, each with its profile and the findings of the last scan. |
| `POST /projects/{id}/scan` | Scans again: the folder it was added from if it still exists, else a fresh worktree of the mirror. Follows a GitHub rename or a new default branch. |
| `PATCH /projects/{id}` | Edits the profile (production flavor, store country, base branch, Shorebird, ids, version files). Edits are kept apart from the scan and applied on top of every scan, so a rescan never undoes them. |
| `DELETE /projects/{id}` | Removes the project. The mirror stays on disk; the folder is never touched. `409` once it has releases or jobs. |

GitHub calls use the token under `github.token` in the secret store (see Secrets above).
`xpd secrets import-gh [--data-dir <path>] [--gh <path>]` puts it there: it runs `gh auth token`
(`GitHubTokenImporter`) and stores the result in the same secret store `xpd serve` opens (the
Keychain on macOS, the encrypted file on Linux), replacing any earlier token. It never prints the
token, only `Imported the GitHub token.`. It exits non-zero with a message when `gh` is not
found, fails or is not logged in (`gh auth login`), or when the secrets are locked. `gh` is
looked up on `PATH`, then at `/opt/homebrew/bin/gh` and `/usr/local/bin/gh` (a `launchd` `PATH`
has neither); `--gh` names it directly. Without a token, adding a project answers `502`. Failures
of GitHub or git answer `502 upstream_error`, a locked secret store `503 secrets_locked`.

The same token is managed over the API (Phase 18c), so a first run in the app can connect GitHub before it
has a project (`apps/xpd/lib/src/api/github`, `GitHubTokenService` in `xp_engine`):

| Route | What it does |
|---|---|
| `GET /github-token` | `{"stored": false}` without a token; with one it asks GitHub (`GET /user`) and answers `stored`, `status` (`verified`, `rejected`, `unreachable`), the `login`, and a `message` and `fix` when GitHub refused it or could not be reached. |
| `PUT /github-token` | `{"token": "..."}`: checks the token with GitHub first and stores it under `github.token` only when GitHub accepts it. `422 credential_rejected` when GitHub refuses it, `502 upstream_error` when GitHub cannot be reached; nothing is stored then. |
| `POST /github-token/import` | What `xpd secrets import-gh` does, over the API: runs `gh auth token` on the engine machine (`gh` on the engine's `PATH`, then `/opt/homebrew/bin/gh` and `/usr/local/bin/gh`), then checks and stores the token as `PUT` does. `422` when `gh` is missing, not logged in or its token is refused. |
| `DELETE /github-token` | Forgets the token (`204`). |

Only `app` and `cli` tokens may change it (`403` otherwise); runner tokens reach none of these routes (ADR 0011).
No response, log or error carries the token, and the engine's masker learns it as soon as the engine sees it.
Adding, scanning and removing announce `project.added`, `project.scanned` and `project.removed` on
`/events`.

The scanner (`packages/xp_engine/lib/src/scan`) is read-only (D-04). It reads the repository only
through the `ScanSource` interface (`list`, `read`, `exists`); `DirectoryScanSource` in `xp_adapters`
is the `dart:io` implementation, and it refuses absolute paths, `..` and symbolic links that leave
the folder. Gradle, Xcode `project.pbxproj`, plists and schemes are read as text, with no tool
installed. The scan finds:

- the apps: one at the root, or the members of a pub workspace or Melos monorepo that have a Flutter
  dependency and an `android/` or `ios/` project;
- the flavors, from Gradle `productFlavors`, `flavorizr.yaml`, Xcode schemes that archive with
  `Release-<flavor>`, and `lib/main_<flavor>.dart` (an app without flavors gets one implicit
  `default` flavor);
- per flavor: the Android application id, the iOS bundle id and signing team, the `Info.plist` and
  whether its versions are literal or `$(FLUTTER_BUILD_*)`, the Shorebird app id, the entrypoint and
  the files a version bump writes;
- per app: CocoaPods or Swift Package Manager, the keystore reference (`key.properties`, never its
  passwords), the `.fvmrc` pin (D-20) and `shorebird.yaml`;
- per repository: the `release/*` branches and default branch of a clone's `.git`, and the GitHub
  Actions and Codemagic workflow files.

Everything suspicious becomes a finding with a severity (`error`, `warning`, `info`), a stable
`code`, a message and a fix. Examples: `bundle_id_platform_mismatch` (Android and iOS differ, "looks
like a typo" when they are one or two characters apart), `bundle_id_config_drift` (flavorizr and the
build files disagree), `plist_literal_version`, `version_files_out_of_sync`, `fvmrc_missing`,
`keystore_properties_missing`, `shorebird_no_flavor_ids`.

The fixtures in `tool/e2e/fixtures` are synthetic repositories shaped like the Mataa customer,
captain and vendor apps, the oneavant companion app, the guest monorepo and the room spike, plus one
that disagrees with itself (`drift`). They hold only the files the scanner reads, with made-up team
and Shorebird ids. `packages/xp_engine/test/scan/fixtures_test.dart` scans each and compares the
profile and findings with `test/scan/goldens/<name>.json`
(`UPDATE_GOLDENS=1 dart test test/scan/fixtures_test.dart` rewrites them; review the diff).

`tool/e2e/smoke_bundle.sh` builds the `xpd` AOT bundle with `dart build cli`, starts it on a free
port with a temporary data directory and checks `/health`, the database, the token guard and a clean shutdown.

## Jobs and processes

A job is a list of steps that run one after the other (D-18). Every step records its state, result and
output as it goes, so a job survives a restart. Jobs are made by dispatching a workflow (see Workflows
and the scheduler) and run by the `JobRunner`; the step types are `command`, which runs a command the
owner declares, `version.bump` and `guard` (see Versions and guards), `build.android`, `build.ios` and
`record.manifest` (see Builds and artifacts), and the ones of the sections after it.

| Route | What it does |
|---|---|
| `GET /jobs/{id}` | The job with its steps. |
| `POST /jobs/{id}/cancel` | Stops the process group of the running step (`SIGTERM`, ten seconds of grace, `SIGKILL`) and returns the cancelled job. |
| `POST /jobs/{id}/resume` | Runs a `failed`, `cancelled`, `interrupted`, `waiting_for_resume` or `waiting_for_approval` job again at its first unfinished step; `{"fromStep": n}` re-runs from step `n`. Answers `202` while the job runs on. |
| `GET /jobs/{id}/logs` | WebSocket: the log lines of the job, replayed from `?after=<seq>` and then live, ending with an `end` frame. |

- **Process groups** (ADR 0003). Every step process starts through a `perl` trampoline that makes it a
  process-group leader, so a cancel stops the whole tree, grandchildren included. `perl` is a runtime
  requirement: `xpd serve` refuses to start without it (it ships with macOS and Debian/Ubuntu).
- **Environment.** A step process gets only `PATH`, `HOME`, `LANG`, `LC_*`, `TMPDIR`, `USER` and
  `SHELL` from the engine, plus what the step declares. Secrets reach a process by environment
  variable name or as a 0600 file in a per-job folder under `<data-dir>/tmp`, deleted when the job
  ends and on engine start; never in the arguments.
- **Output.** Every line is masked against the known secret values (`xp_secrets`) before it is stored
  or streamed, and gets a sequence number and a time. Lines are written to
  `<data-dir>/logs/<jobId>/<ordinal>-<kind>.log`, one JSON object per line. The `seq` of the log
  WebSocket counts the lines of the whole job, so a client reconnects with the last `seq` it saw.
  The log file and the step parser never lose a line: a slow reader slows the process down. Live
  views have a bounded queue that drops its oldest lines and says so with a `gap` frame.
- **Resume and side effects.** A step with side effects (a store upload, a tag) is never repeated by
  the engine on its own. After an interruption such a job is `waiting_for_resume`; an explicit resume
  first asks the step whether its work exists already (`alreadyDone`) and skips it if so. A job whose
  interrupted step has no side effects is resumed when the engine starts.
- **Restart.** On start `xpd` stops the process groups it recorded for jobs left `running` (`SIGTERM`,
  grace, `SIGKILL`) before it marks them interrupted. On `SIGTERM` or `SIGINT` it stops running jobs
  the same way.
- **Sleep.** While a job runs the machine is kept awake: `caffeinate -i -w <xpd pid>` on macOS,
  `systemd-inhibit` on Linux. Without the tool `xpd` warns and carries on.

## Versions and guards

Phase 8 adds the release model: how versions, build numbers, branches and tags are handled. No
endpoint exposes it; workflows call it (see Workflows and the scheduler).

- **Version files.** A version is `x.y.z+build`. `version.bump` writes it into the app's `pubspec.yaml`
  and every plist the flavor lists in `versionFiles`, by text replacement so the diff stays one line
  per key, and commits them in the job's worktree as `chore(release): x.y.z+build`. A plist key
  must match exactly once; `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)` are left alone.
  Nothing is pushed. The step is done when the head already holds the version.
- **Build numbers** (D-11). One counter per app in `app.build_counter`. `BuildNumberAllocator`
  allocates at dispatch: one more than the largest of the store's builds, the build numbers in the
  tags and the counter, in one atomic `UPDATE ... RETURNING`. A number is never handed back.
- **Release model** (`project.release_model`). Branch and tag names are patterns with `{version}`,
  `{build}`, `{n}` (OTA patch), `{app}` and `{flavor}`. Defaults: `release/{version}`,
  `v{version}+{build}` and `v{version}+{build}-p{n}`. `ReleaseBranchCutter` cuts
  `release/<x.y.z>` at the dispatched commit and never forces.
- **Guards.** The `guard` step runs the checks a workflow lists and fails if any fails, naming each
  problem and its fix: `source` (clean worktree on the dispatched commit, no `pubspec_overrides.yaml`,
  no local path dependency), `appStoreTrain` (ITMS-90186 closed train), `versionSync`, `patchTarget`,
  `newReleaseNumber`, `patchNativeDiff`, `playTargetSdk` and `buildNumberReuse`. What a check needs
  from a store (train state, Play's target API level, build numbers, Shorebird releases) comes from
  an interface; `xpd` registers the checks that need none and adds the others with the store
  adapters (Phase 10).

## Toolchain

Phase 9a decides which tools a job runs with (D-20). The build steps of Phase 9b are the first callers
(see Builds and artifacts); no endpoint exposes this.

- **Flutter** (`FlutterResolver`, `packages/xp_engine/lib/src/toolchain`). Flutter is pinned per app by
  its `.fvmrc`, which the scan reads into the profile (`flutterVersion`). `resolve(version)` returns a
  concrete SDK folder, its Flutter and Dart versions and where it came from:
  1. **fvm**, if it is installed: `fvm api list` (JSON, fvm 3 and 4) gives the SDK it has cached, at
     whatever path fvm's cache is; a missing version is installed with `fvm install`. Pass
     `fvmExecutable` a full path when the engine runs with a short `PATH` (a LaunchAgent).
  2. **XPath's cache**, `<data-dir>/toolchains/flutter/<version>`, when there is no fvm or fvm cannot
     install the version. A hit is used as it is; a miss goes to the `FlutterInstaller` port. Only exact
     versions (`3.47.6`) are downloaded.
  `GitFlutterInstaller` (`xp_adapters`) runs `git clone --depth 1 --branch <version>` of the Flutter
  repository into a temporary folder of the cache, renames it to the version, then runs `flutter
  --version --machine` there to precache the Dart SDK. A failure leaves nothing in the cache.
  A pin that is missing, unreadable, not a version, or not exact when fvm is absent, a failed download
  and a cached SDK that does not run are `FlutterResolutionException`s (a `ToolchainException`) with
  a `failure` code and a fix. A Shorebird patch calls `resolve` with the Flutter version recorded for
  the release instead of the current pin.
- **Shorebird, gh and Xcode** (`ToolProber`). Managed per machine, never installed or updated by XPath:
  `shorebird --version`, `gh --version`, and `xcode-select -p` followed by `xcodebuild -version`
  (`xcodebuild` is only run once an Xcode is selected, because macOS answers it with a dialog on a Mac
  without developer tools). On Linux Xcode is reported as `unsupported`. No minimum version is enforced;
  the versions are recorded. Each `ToolReport` is `available`, `missing`, `failed` or `unsupported`, with
  a message that says how to fix it. The parsers (`version_parsers.dart`) are tested against output
  captured from real runs, kept in `packages/xp_engine/test/src/toolchain/fixtures`.
- **Recorded per job** (`JobTools`). The Flutter, Dart, Shorebird, gh and Xcode versions of a job are
  saved with `JobRepository.saveTools` into the `tools` JSON column of `job` (schema version 4) and read
  back with `tools`. `JobTools.from(flutter:, reports:)` builds the record from a resolution and the
  probes.

## Builds and artifacts

Phase 9b adds the steps that build an app and the store that keeps what they produce. Workflows start
them (see Workflows and the scheduler); `tool/e2e/build_fixture_apk.sh` still builds the fixture with a
job made through `JobRunner` alone.

- **`build.android` / `build.ios`** (`packages/xp_engine/lib/src/steps/build`). Each runs `flutter build
  apk|appbundle|ipa --release` of the Flutter SDK that `FlutterResolver` resolves for the app's `.fvmrc`
  pin, in the app directory of the job's worktree, through the process supervisor (own process group,
  masked and logged output, cancellation). The flags are the ones of the reference scripts:
  `--flavor`, `--target` (`lib/main_<flavor>.dart`), `--build-name` and `--build-number` from the job's
  version, `--dart-define-from-file`, `--obfuscate --split-debug-info` (the debug info goes to
  `build/xpath/debug-info/<platform>` of the app, for the symbols step of Phase 9c) and, for iOS,
  `--export-options-plist`. Before it builds, a step resolves Flutter, probes the other tools and saves
  their versions for the job (`JobRepository.saveTools`). Signing inputs never go in the arguments: the
  step input names secrets (`secretEnvironment`: variable to secret key; `secretFiles`: variable to the
  path of a 0600 file that is deleted when the job ends), which the job runner reads from the secret store.
  Which credential maps to which variable is decided when a workflow is dispatched (the keystore reaches a build as `XPATH_KEYSTORE_*`; see Workflows and the scheduler). `build.ios` fails
  with "needs macOS (ios-sign), or a Linux runner set up for iOS builds (ios-linux)" on any other machine.
- **`build.ios` on Linux** (ADR 0014). On a runner with `XP_IOS_LINUX_DIR`, `build.ios` runs
  omarchy-apple-dev instead of Xcode: `flutter/setup.sh` once per Flutter version in an install of its own
  (`toolchains/flutter-ios-linux/<version>` of the runner, resolved without fvm; the script replaces the
  iOS `gen_snapshot` of the install it runs on, so it is never the SDK other builds use, and installs no job
  used for 30 days are deleted), then `flutter/build.sh <app> KEY=VALUE...` (`BUILD_NAME`, `BUILD_NUMBER`,
  `SPLIT_DEBUG_INFO` and `DART_OBFUSCATION` for an obfuscated build, the dart defines as arguments) and
  `flutter/ship.sh <app>` without `--upload` (`ASC_EXPORT_OPTIONS`, `ASC_ENTITLEMENTS_PATH` when
  `ios/Runner/Runner.entitlements` exists). It signs with the flavor's Apple Distribution identity and the
  App Store profile the engine made with the flavor's ASC key (`linuxSigning`: `ASC_SIGNING_KEY`,
  `ASC_SIGNING_CERT`, `ASC_PROFILE`); the ASC key never reaches the runner. The IPA is
  `build/ios-linux/Runner-store.ipa`, the dSYMs `build/ios-linux/dSYMs`, and the job's tools record "Linux,
  omarchy-apple-dev `<commit>`".
- **Freshness marker** (`BuildFiles.markBuildStart`, `BuildOutputs`). `build/` is not cleaned between
  runs, so a failed build can leave the artifact of an earlier one. Right before the build the step asks
  the file system for the current time (it writes and stats a temporary file, so the time is in the same
  clock as the modification times of the outputs). Only a file written after that time is taken; one that
  is older fails the step with a message that names it. The IPA folder is also emptied first, because
  `flutter build ipa` names the IPA after the app, not the flavor.
- **Discovery.** An APK is looked for at `build/app/outputs/flutter-apk/app-<flavor>-release.apk` and
  `.../apk/<flavor>/release/`, an AAB at `.../bundle/<flavor>Release/app-<flavor>-release.aab` (no
  flavor: `app-release.*` and `bundle/release`), with the same file name anywhere below
  `build/app/outputs` as the fallback if a Gradle upgrade moves them. The name always carries the flavor:
  a loose `*.apk` would return the dev APK for a prod build. An IPA is the one in `build/ios/ipa`.
- **Artifact store** (`ArtifactRecorder`, `DirectoryArtifactStore`, `SqliteArtifactRepository`). The file is
  copied to `<data-dir>/artifacts/<jobId>/<flavor>-<version>.<ext>` (`dev-1.2.3+45.apk`) under a
  temporary name and renamed, and one pass over the bytes gives its size and SHA-256. The record goes to
  the `artifact` table (schema version 5 adds `created_at` and one row per job and path), so a step that
  runs again replaces its artifact and keeps its id and its pin. `alreadyDone` of a build step is true
  when the job has an artifact of that name whose file still has the recorded SHA-256.
- **`record.manifest`.** Stores `manifest.json` as an artifact of kind `manifest`: version, build and
  tag, the built commit (head of the worktree) and the dispatched one, whether the worktree was dirty,
  flavors, the tool versions of the job, the SHA-256 of `pubspec.lock` and of the dart-define file, every
  artifact of the job with its SHA-256, and when the job started and the manifest was written.

| Route | What it does |
|---|---|
| `GET /jobs/{id}/artifacts` | The artifacts of a job, oldest first. `404` for a job that does not exist. |
| `GET /artifacts/{id}` | One artifact: id, job, kind, name, size, SHA-256, pinned, creation time. The place in the store is not shown. |
| `GET /artifacts/{id}/download` | Streams the file with `Content-Length`, `X-Content-SHA256` and a `Content-Disposition` with its name. `404` if the file left the store. |
| `POST /artifacts/{id}/pin`, `POST /artifacts/{id}/unpin` | Pins an artifact so that the housekeeping of Phase 12c keeps it, or lets it go. Idempotent. |

`tool/e2e/build_app` is a minimal Flutter app (`dev` and `prod` Gradle flavors, `lib/main_<flavor>.dart`,
`.fvmrc` pinned to 3.47.6, release builds signed with the debug key so that no secret is needed). It is not
one of the scanner fixtures. `tool/e2e/build_fixture_apk.sh` builds its dev APK through the engine: the Dart
program `apps/xpd/tool/build_fixture_apk.dart` wires what `xpd serve` wires and runs one job
(`version.bump`, `build.android`, `record.manifest`) in a worktree of a throwaway repository made from the
fixture, with a throwaway data directory and no secret store; the script then checks, with `wc` and
`sha256sum`/`shasum`, that the APK is where the engine says, has the size and SHA-256 it recorded, is a zip,
and that the manifest lists it. It needs the Android SDK (`ANDROID_HOME`, `ANDROID_SDK_ROOT` or the default
Android Studio location) and the pinned Flutter first on `PATH`. Set `XPATH_E2E_FLUTTER_SDK` to use an SDK
folder that already is the pinned version instead of letting the resolver find it. On Linux the machine
must be x86-64: Flutter ships no Android release compiler (`gen_snapshot`) for Linux on ARM.

## Shorebird, symbols and post-build checks

Phase 9c adds five steps next to the build steps (`packages/xp_engine/lib/src/steps/{shorebird,symbols,build}`).
Real Shorebird is never run by the tests: a fake process context asserts the command line, and the JSON the
adapter parses is a fixture that follows the documented `--json` output.

- **`shorebird.release`** runs `shorebird release android|ios` in the app, with `--flavor`, `--target`,
  `--build-name`, `--build-number`, `--flutter-version=<resolved pin>`, `--artifact apk|aab` (Android),
  `--export-options-plist` (iOS) and `--split-debug-info` (obfuscated builds). The app's own flags
  (`--dart-define-from-file`, `--obfuscate`) go after `--`, which is where Shorebird forwards them to
  `flutter build`. It stores the APK, the AAB (an APK release also stores the AAB that Shorebird builds with
  it) or the IPA as artifacts, and saves the Flutter version of the release (`ShorebirdReleaseRepository`,
  table `shorebird_release`, keyed by Shorebird app id, version and platform). It has a side effect;
  `alreadyDone` asks `ShorebirdReleases` (`shorebird --json releases list --app-id <id>`) whether the
  version is complete for the platform. `CI=true` keeps the CLI from prompting.
- **`shorebird.patch`** looks up the Flutter version of the release it patches, first in that record, then in
  the release data Shorebird lists, and fails with a fix hint if neither knows it. It resolves that exact SDK
  (`FlutterResolver`, so the job's recorded Flutter is the release's, not the app's current pin) and runs
  `shorebird patch android|ios --release-version=<x.y.z+build>`. `shorebird patch` has no `--flutter-version`
  option: the CLI builds with the Flutter revision of the release by itself, so none is passed. On iOS the IPA
  the patch builds is deleted afterwards (it carries the release's build number).
- **The Shorebird key** is `SHOREBIRD_TOKEN` (an `sb_api_*` API key; `login:ci` tokens stopped working on
  2026-10-01). A step input names the secret (`tokenSecret`, a key in the secret store) and the job runner
  puts the value in the environment of the process, never in the arguments. The key is a `shorebird`
  credential (see Credentials).
- **`symbols.archive`** keeps the R8 `mapping.txt` (`mapping`), the zipped dSYMs of the iOS archive (`dsym`)
  and the zipped debug info of an obfuscated build (`shorebird_symbols`, the only kind for it), each with
  its SHA-256. A symbol that is not there is a warning in the result, as in the reference script, not a
  failure. `alreadyDone` holds when everything that can be found is stored and still has its SHA-256.
- **`build.verifyCompiledConfig`** proves that the configuration reached the binary. It reads the AOT snapshot
  (`lib/*/libapp.so` of an APK, `base/lib/*/libapp.so` of an AAB, `App.framework/App` of an IPA) of a stored
  package and looks for the expected strings: literal `needles`, and the values of `keys` of the
  `--dart-define-from-file` file (a URL is reduced to its host). A string that is missing fails the step with
  a message that says what was dropped; a package without a snapshot is skipped.
- **`ios.stripAndReexport`** deletes named frameworks from `build/ios/archive/Runner.xcarchive`, runs
  `xcodebuild -exportArchive` again so that Xcode signs the smaller bundle, and stores the new IPA over the
  one `build.ios` stored (same name, same artifact id).

`xpd serve` registers all five.

## Tests and analyze

Phase 9d adds the `test` and `analyze` steps (`packages/xp_engine/lib/src/testing`) and the endpoints that
show a test run (D-21). Device integration tests are out of scope. Real Flutter is never run by the unit tests:
the parsers read output captured from Flutter 3.47.6 on a throwaway app
(`packages/xp_engine/test/src/testing/fixtures`, with the machine's own directory replaced by `/work/app`).

- **`test`** runs `flutter test --machine` of the job's pinned SDK in the app (plus one `--tags` with the tags of its
  input, which a test must all match, and its `paths`) and reads the JSON events as they arrive (`MachineTestParser`). Lines that
  are not JSON objects are noise (Flutter prints blank lines and `[{"event":...}]` notices). A test is
  identified by its file relative to the app and its full name with the names of its groups, so the identity
  is the same in every worktree. It ends `passed`, `failed` (an expectation), `errored` (it threw) or
  `skipped`. A test file that does not load, and a failing `setUpAll`, are tests of their own
  (`loading test/x_test.dart`, `group (setUpAll)`) that errored, so they fail a run like any test. Two tests
  of a file with the same full name count as one, and the worse outcome wins. Messages and stack traces are
  kept, cut at 4,000 characters.
- **The step fails only on new failures** against the baseline, not on failures the baseline has. It also
  fails when the run was cancelled, printed no JSON, stopped before its `done` event (a crash) or ran no
  test. Only a run that finished is stored.
- **The run** is stored in `test_run`, one per job (a step that runs again replaces it): the tests in a compact
  JSON document (per file, the names that passed or were skipped, and the failures with their message), the
  diff against the baseline it was compared with, and `baseline`. A `test_run.completed` event goes out.
- **The diff** (`diffTestRuns`): `newFailures` fail now and did not fail in the baseline, or are not in it;
  `fixed` failed in the baseline and pass now; `missing` are in the baseline and not in the run; `stillFailing`
  counts the failures the baseline has. A run of some `paths` expects only the files it ran; a run with `tags`
  reports no missing tests. Without a baseline every failure is new.
- **The baseline is the last green run on the base branch.** Green means no new failures against the baseline
  before it, so failures a project has not fixed yet (27 of them, say) do not stop it from having a baseline;
  a run that fixes some raises the baseline. Only a complete run (no `paths`, no `tags`) of the base branch
  counts. The first run of the base branch has nothing to be green against, so it **seeds** the baseline as it
  is, failures included, and passes (`seeded` in the step result); a run of any other branch with no baseline
  fails on every failure and says to run the base branch first. Seeding is the one place where a red run
  becomes the reference: to start over, run the tests on the base branch after fixing the failures that matter.
  Housekeeping must keep the baseline row (Phase 12c): `test_run` is deleted with its job.
- **`analyze`** runs `flutter pub get` and then `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`.
  Flutter's analyzer has no machine-readable output, so the text is parsed (`severity • message •
  path:line:column • code`; the summary line goes to standard error). `--no-pub` alone analyzes a fresh worktree
  against no packages and reports every import as an error, hence the `pub get`. There is no baseline for the
  analyzer: the step fails on any issue of the input's `failOn` severity or worse, `error` by default, and
  records the counts and the first 200 issues, the worst first, in its result. A run with no summary line, or
  with fewer issues read than the summary announces, fails, since an error could be hiding in it.

| Route | What it does |
|---|---|
| `GET /jobs/{id}/tests` | The run of the job with its counts and its diff, and a page of its tests: the failures unless `?status=passed,failed,errored,skipped` says otherwise, `?limit=` (default 200, at most 1000) and `?offset=`. `404` if the job ran no tests. |
| `GET /projects/{id}/tests/baseline` | The current baseline of every app and branch of the project. |

`xpd serve` registers both steps.
