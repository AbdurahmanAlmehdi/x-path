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
columns of `project`; version 3 adds what the job runner records to `job` and `job_step`.

Secrets (`packages/xp_secrets`) live on the engine machine behind the `SecretStore` interface of
`xp_engine`; `createSecretStore` picks the implementation for the platform.

- **macOS: Keychain** (ADR 0004). Each operation runs one `security -i` and sends one quoted command
  line on stdin, so a value never appears in `ps`. Values are stored as base64 of their UTF-8 bytes,
  because `security -i` reads one line and prints non-ASCII passwords as hex; one command line is
  limited to 4094 bytes, so a secret can be about 3 KB (less with a long key name). The service is `dev.xpath.<scope>`.
- **Linux: encrypted file.** `secrets.enc` in the data directory, sealed with XChaCha20-Poly1305
  under a 32-byte master key: `$CREDENTIALS_DIRECTORY/xpath-master-key` (systemd
  `LoadCredentialEncrypted=`) if set, else `master.key` in the data directory (mode 0600, created on
  first use, refused if group or world can read it).
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

GitHub calls use the token under `github.token` in the secret store (see Secrets above). Nothing
imports the token of the GitHub CLI from the command line yet: `GitHubTokenImporter` exists but no
command runs it. Without a token, adding a project answers `502`. Failures
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
which runs a command the owner declares, `version.bump` and `guard`; see Versions and guards).

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

CI enforces the same thresholds on macOS. Linux CI runs the same tests without the gate.
Coverage counts the files that tests import, so keep each package's barrel (`lib/<name>.dart`)
exporting everything.

### Test tags

Every package's `dart_test.yaml` declares these tags.

| Tag | Meaning | Default run |
|---|---|---|
| `contract` | Checks API responses against `openapi.yaml` with `package:xp_api/testing.dart`. | runs |
| `process` | Spawns real child processes. | runs |
| `macos` | Needs macOS (Keychain, SMAppService, ...). | runs on macOS only |
| `integration` | Needs external tools or services. | skipped; run with `dart test --run-skipped -t integration` |

Because `integration` tests are skipped by default, they are not part of the coverage run.

## Continuous integration

`.github/workflows` has one workflow per package, each filtered to the paths that can affect it
(the package, the packages it may depend on, the root `pubspec.yaml` and `.fvmrc`). They call the
reusable workflows of
[very_good_workflows](https://github.com/VeryGoodOpenSource/very_good_workflows). The workspace
has Flutter members, so even `dart pub get` needs the Flutter SDK; every package therefore uses the
`flutter_package` workflow, pinned to Flutter 3.47.6, instead of `dart_package`. CI therefore runs
`very_good test` for Dart packages too; locally `melos run test:coverage` uses `very_good dart test`.

- Dart packages run on macOS (with the coverage gate) and on Linux (same tests, no gate).
- `xp_desktop` and `xp_macos_services` run on macOS only.
- `layers.yaml` runs the layer check.
- `semantic_pull_request.yaml`, `spell_check.yaml` and `license_check.yaml` cover the rest. The
  spell check reads `README.md` and `docs/adr`; the planning documents are ignored in
  `.github/cspell.json`.

Pull request titles follow [Conventional Commits](https://www.conventionalcommits.org).

## License

Apache-2.0. See [LICENSE](LICENSE).
