# XPath

XPath is an open source (Apache-2.0), self-hosted release tool for Flutter apps.

A headless engine, `xpd`, owns projects, secrets, jobs and store status. Four clients talk to it
over HTTP/JSON plus one WebSocket:

- a Flutter macOS app (`apps/xp_desktop`),
- the `xp` command-line client (`apps/xp`),
- `xp mcp`, an MCP server for agents,
- `xp runner`, remote runners on other Macs and Linux machines.

You point it at a repo, it scans the app, and from then on it builds, tests, signs, uploads, tags
and tracks releases to App Store Connect, Google Play, Firebase App Distribution and Shorebird.
It writes nothing to the repo except release-model git changes.

> **Status:** pre-1.0, under construction. The workspace, tooling and CI are in place; the
> features land phase by phase. See [the plan](docs/plan/2026-10-13-feat-xpath-release-tool-plan.md).

## Repository layout

| Path | What it is |
|---|---|
| `apps/xpd` | Engine entrypoint (Dart). Wires the implementations and owns the HTTP handlers. |
| `apps/xp` | The `xp` CLI (Dart). |
| `apps/xp_desktop` | The macOS app (Flutter). |
| `packages/xp_api` | Models, error codes and events shared by every client and the engine. |
| `packages/xp_client` | HTTP and WebSocket client for the engine API. |
| `packages/xp_engine` | Domain and application logic. Framework-free; defines interfaces only. |
| `packages/xp_adapters` | Implements the engine interfaces: SQLite, git, GitHub, stores, processes. |
| `packages/xp_secrets` | Implements the secret store: Keychain, encrypted file, log masking. |
| `packages/xp_repositories` | Repositories for the desktop app, built on `xp_client`. |
| `packages/xp_macos_services` | Flutter package for macOS platform services. |
| `tool` | Repository tooling (`xp_tool`): the layer check, and `tool/e2e` with the smoke test and the fixture repositories. |
| `docs` | Plan, ADRs, research and design brief. |

Everything is one [Dart pub workspace](https://dart.dev/tools/pub/workspaces) (ADR 0001) with
[Melos](https://melos.invertase.dev) 8 configured under `melos:` in the root `pubspec.yaml`.

### Dependency direction

`tool/check_layers.dart` enforces this on every `import` and `export` directive in `lib/`,
`test/` and `bin/`, and on every `pubspec.yaml`. The rules live in
`tool/lib/src/layer_rules.dart`.

- `xp_engine` depends on `xp_api` only, plus a short allowlist of pure utility packages.
- `xp_adapters` and `xp_secrets` may depend on `xp_engine` and `xp_api`.
- `xp_client` depends on `xp_api`; `xp_repositories` on `xp_client` and `xp_api`.
- `xpd` wires the engine, the adapters and the secret stores.
- The desktop app never imports `xp_engine`, `xp_adapters` or `xp_secrets`.

## Development setup

The repo pins Flutter 3.47.6 (Dart 3.13.5) in `.fvmrc`. Install [fvm](https://fvm.app) and run
`fvm install`; that creates `.fvm/flutter_sdk`, which is gitignored.

The Dart that happens to be on your `PATH` may be older, and so may the Dart behind globally
activated tools such as `melos` and `very_good`. Put the pinned SDK first in every shell you
use for this repo:

```sh
export PATH="$PWD/.fvm/flutter_sdk/bin:$HOME/.pub-cache/bin:$PATH"
dart pub global activate melos
dart pub global activate very_good_cli 1.5.0
dart pub get   # resolves every package, including the Flutter ones, in one go
```

Every member needs the Flutter SDK to resolve, so there is no Dart-only way to run
`dart pub get` here.

### Melos scripts

Run them from the repo root with `melos run <name>`.

| Script | What it does |
|---|---|
| `analyze` | `dart analyze --fatal-infos` over the workspace. |
| `format` | Fails if any file needs formatting. Writes nothing. |
| `check:layers` | Runs `tool/check_layers.dart`. |
| `test` | Runs every package's tests, no coverage. |
| `test:coverage` | Runs every package's tests and enforces its coverage threshold. |
| `test:contract` | Runs `dart test --tags contract test/contract` in the packages that have a `test/contract/` directory (`xp_api`, `xpd`). Put new contract tests there, so the script visits the package; plain `dart test --tags contract` exits 79 in a package without a match. |

The root `analysis_options.yaml` excludes `docs/**` (the design reference files import packages the
workspace does not install), so `dart analyze --fatal-infos` at the root covers the code only.

The full local gate:

```sh
dart pub get && dart analyze --fatal-infos && dart format --set-exit-if-changed . \
  && dart run tool/check_layers.dart && melos run test:coverage
```

## Running the engine

```sh
dart run apps/xpd/bin/xpd.dart token create --name "My Mac" --kind app   # prints the token once
dart run apps/xpd/bin/xpd.dart serve                                      # http://127.0.0.1:7480
```

- `xpd serve [--host 127.0.0.1] [--port 7480] [--data-dir <path>]` listens on loopback by default.
  Any other `--host` exposes the engine to the network without encryption, and prints a warning.
  SIGINT and SIGTERM close the server and its WebSocket connections cleanly.
- `xpd token create --name <name> --kind app|cli|mcp|runner` creates a device token and prints it
  once on stdout. Only its SHA-256 is stored. A running engine accepts it at once.
- `xpd secrets import-gh [--data-dir <path>] [--gh <path>]` stores the token of the GitHub CLI in
  the engine's secret store (see Projects and scans).
- Every route except `GET /health` and `GET /version` needs `Authorization: Bearer <token>`.
- `GET /events` is a WebSocket. Each frame carries a `seq`; reconnect with `?after=<last seq>` to
  receive what was missed. [`packages/xp_api/openapi.yaml`](packages/xp_api/openapi.yaml)
  documents the API.

The data directory holds the SQLite database, `xpath.db` (ADR 0002). It is
`--data-dir`, else `$XPATH_DATA_DIR`, else `~/Library/Application Support/XPath` on macOS or
`$XDG_DATA_HOME/xpath` (`~/.local/share/xpath`) on Linux.

The database (`packages/xp_adapters/lib/src/sqlite`) is opened with WAL, a busy timeout and foreign
keys, through one connection per process. Its schema is the ordered list in `migrations.dart`,
tracked by `PRAGMA user_version`; each migration runs in a transaction. Before an existing
database is migrated, `xpd` copies it to `xpath.db.bak-v<old version>`. A migration is never
edited once released: add a new one and a golden `test/src/sqlite/snapshots/v<N>.sql`
(`UPDATE_GOLDENS=1 dart test test/src/sqlite/migrations_test.dart` writes it). Events older than
seven days are pruned; their sequence numbers are never reused. Schema version 2 adds the scan
columns of `project`; version 3 adds what the job runner records to `job` and `job_step`; version 4
adds the tool versions of a job; version 5 adds the time and a unique path to `artifact`.

Secrets (`packages/xp_secrets`) live on the engine machine behind the `SecretStore` interface of
`xp_engine`; `createSecretStore` picks the implementation for the platform.

- **macOS: Keychain, plus a file for large secrets** (ADR 0004, ADR 0008). Each Keychain operation
  runs one `security -i` and sends one quoted command line on stdin, so a value never appears in
  `ps`. Values are stored as base64 of their bytes, because `security -i` reads one line and prints
  non-ASCII passwords as hex. One command line is limited to 4094 bytes, so the Keychain only takes
  values whose base64 form is at most 2,048 characters (1,536 bytes). A larger secret, such as an
  Android keystore, goes to `secrets.enc` in the data directory (the file described under Linux),
  whose 32-byte key is a random item in the Keychain, created on first use. A key lives in one
  place only: writing a secret that grew or shrank moves it. Services are
  `ly.abdurahman.xpath.credentials` for the secrets and `ly.abdurahman.xpath.master` for the file
  key (ADR 0005). A locked Keychain locks the whole store, large secrets included.
- **Linux: encrypted file.** `secrets.enc` in the data directory, sealed with XChaCha20-Poly1305
  under a 32-byte master key: `$CREDENTIALS_DIRECTORY/xpath-master-key` (systemd
  `LoadCredentialEncrypted=`) if set, else `master.key` in the data directory (mode 0600, created on
  first use, refused if group or world can read it).
- **Text and bytes.** `SecretStore` has `read`/`write` for text (UTF-8) and `readBytes`/`writeBytes`
  for binary values such as keystores; both use the same keys. `read` of a value that is not UTF-8
  is an error.
- **Secrets locked** (D-10). A locked Keychain, a missing or unreadable master key, or a key that does
  not open the file makes the store throw `SecretsLockedException` and set `status` to
  `SecretsStatus.locked` (`statusChanges` announces it). The engine never prompts.
- **Log masking.** `SecretMasker` replaces known secret values with `***` in process output. A
  multi-line secret is masked line by line, overlapping secrets are merged, lines shorter than 6
  characters are ignored, and `MaskingStream` masks a secret split between two chunks.

## Projects and scans

A project is a GitHub repository, keyed by its GitHub repository id (D-05). The folder you pick only
identifies the repository and seeds the first scan; builds run from the engine's own bare mirror.
All routes need a device token.

| Route | What it does |
|---|---|
| `POST /projects` | Adds a project from `{"path": "/abs/clone"}` (reads its `origin`) or `{"remote": "owner/name"}` (or a GitHub URL), asks GitHub for the repository, sets up the mirror and scans. `409` if it is a project already. |
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
output as it goes, so a job survives a restart. Dispatching jobs from workflows comes in a later
phase; for now the engine runs jobs created through `JobRunner` (the built-in steps are `command`,
which runs a command the owner declares, `version.bump` and `guard`, see Versions and guards, and
`build.android`, `build.ios` and `record.manifest`, see Builds and artifacts).

| Route | What it does |
|---|---|
| `GET /jobs/{id}` | The job with its steps. |
| `POST /jobs/{id}/cancel` | Stops the process group of the running step (`SIGTERM`, ten seconds of grace, `SIGKILL`) and returns the cancelled job. |
| `POST /jobs/{id}/resume` | Runs a `failed`, `cancelled`, `interrupted` or `waiting_for_resume` job again at its first unfinished step; `{"fromStep": n}` re-runs from step `n`. Answers `202` while the job runs on. |
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
endpoint exposes it yet; workflows call it from Phase 11.

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
them from Phase 11; until then a job is created through `JobRunner`, as `tool/e2e/build_fixture_apk.sh`
does.

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
  Which credential maps to which variable is a workflow matter (Phase 10c, Phase 11). `build.ios` fails
  with "needs macOS (ios-sign)" on any machine that is not a Mac.
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

## Testing

### Coverage policy

| Threshold | Packages |
|---|---|
| 100% lines | `xp_api`, `xp_client`, `xp_engine`, `xp_repositories` (and all blocs) |
| 90% lines | everything else: `xp_adapters`, `xp_secrets`, `xp_macos_services`, `xpd`, `xp`, `xp_desktop`, `xp_tool` |

Where real OS calls sit behind fakes, the real-OS tests are tagged (below) and the fakes carry the
coverage. `*.g.dart` files are excluded from coverage.

`melos run test:coverage` runs `very_good dart test` (Dart packages) or `very_good test` (Flutter
packages) in each package with `--min-coverage <threshold>`. It exits non-zero if any package is
below its threshold. The thresholds are the three `test:coverage:*` scripts in the root
`pubspec.yaml`: a package not named in `test:coverage:strict` gets the 90% floor.

GitHub CI runs on Linux only (no GitHub-hosted macOS runners) and enforces the same
thresholds there. `macos`-tagged tests and the macOS gate run locally: run
`melos run test:coverage` on a Mac before merging to `main`.
Coverage counts the files that tests import, so keep each package's barrel (`lib/<name>.dart`)
exporting everything.

### Test tags

Every package's `dart_test.yaml` declares these tags.

| Tag | Meaning | Default run |
|---|---|---|
| `contract` | Checks API responses against `openapi.yaml` with `package:xp_api/testing.dart`. Lives in `test/contract/`; run with `melos run test:contract`. | runs |
| `process` | Spawns real child processes. | runs |
| `macos` | Needs macOS (Keychain, SMAppService, ...). | runs on macOS only |
| `integration` | Needs external tools or services. | skipped; run with `dart test --run-skipped -t integration` |

Because `integration` tests are skipped by default, they are not part of the coverage run.

## Continuous integration

`.github/workflows` has one workflow per package, each filtered to the paths that can affect it
(the package, the packages it may depend on, the root `pubspec.yaml` and `.fvmrc`). They call the
reusable workflows of
[very_good_workflows](https://github.com/VeryGoodOpenSource/very_good_workflows). The workspace
has Flutter members, so even `dart pub get` needs the Flutter SDK; every job installs Flutter 3.47.6.

- Every package runs on Linux only, with its coverage gate: Dart packages through the repo's
  `dart_package.yaml` (`very_good dart test`, as locally), Flutter packages through the VGV
  `flutter_package` workflow. No GitHub-hosted macOS runners.
- `layers.yaml` runs the layer check.
- `smoke_bundle.yaml` runs `tool/e2e/smoke_bundle.sh` on Ubuntu (run it locally on macOS): it builds the `xpd` AOT
  bundle, starts it and checks `/health`, the SQLite build hook, token authentication and a clean
  shutdown. It runs when `apps/xpd`, `packages`, `tool/e2e` or the root `pubspec` files change, and
  needs `dart` 3.13, `curl` and `perl`.
- `semantic_pull_request.yaml`, `spell_check.yaml` and `license_check.yaml` cover the rest. The
  spell check reads `README.md` and `docs/adr`; the planning documents are ignored in
  `.github/cspell.json`.

Pull request titles follow [Conventional Commits](https://www.conventionalcommits.org).

## License

Apache-2.0. See [LICENSE](LICENSE).
