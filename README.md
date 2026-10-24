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

> **Status:** 1.0. The engine, the `xp` CLI, `xp mcp`, remote runners and the macOS app are released
> together; install the notarized Mac app with `brew trust abdurahmanalmehdi/tap && brew install --cask
> abdurahmanalmehdi/tap/xpath`, or download the DMG, the Linux bundles or the Docker image from
> [Releases](https://github.com/AbdurahmanAlmehdi/x-path/releases). See [try it locally](docs/guide/try-it-locally.md),
> [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Agent skills

`skills/` holds [Agent Skills](https://agentskills.io) that teach a coding agent (Claude Code,
Cursor, Codex and others) how to work with XPath:

| Skill | For |
|---|---|
| `xpath-release` | Operating XPath through `xp` and `xp mcp`: dispatching builds and releases, following logs, reading store status. It never approves a gate. |
| `xpath-workflows` | Writing and validating workflow YAML. |
| `xpath-setup` | Installing XPath, tokens, credentials, runners and troubleshooting. It never asks for a secret in chat. |
| `xpath-contributing` | Changing XPath itself. |

Install them with the [`skills`](https://www.npmjs.com/package/skills) CLI, from the repository of the
app the agent will release (skills install into the current project):

```sh
npx skills add AbdurahmanAlmehdi/x-path                                   # pick skills and agents
npx skills add AbdurahmanAlmehdi/x-path --list                            # list them
npx skills add AbdurahmanAlmehdi/x-path --skill xpath-release -a claude-code -y
npx skills add AbdurahmanAlmehdi/x-path --skill '*' -a claude-code -g -y  # all, for every project
```

## Repository layout

| Path | What it is |
|---|---|
| `apps/xpd` | Engine entrypoint (Dart). Wires the implementations and owns the HTTP handlers. |
| `apps/xp` | The `xp` CLI and `xp mcp` (Dart). |
| `apps/xp_desktop` | The macOS app (Flutter). |
| `packages/xp_api` | Models, error codes and events shared by every client and the engine. |
| `packages/xp_client` | HTTP and WebSocket client for the engine API. |
| `packages/xp_engine` | Domain and application logic. Framework-free; defines interfaces only. |
| `packages/xp_adapters` | Implements the engine interfaces: SQLite, git, GitHub, stores, processes. |
| `packages/xp_secrets` | Implements the secret store: Keychain, encrypted file, log masking. |
| `packages/xp_repositories` | Repositories for the desktop app, built on `xp_client`. |
| `packages/xp_macos_services` | Flutter package for macOS platform services. |
| `tool` | Repository tooling (`xp_tool`): the layer check, and `tool/e2e` with the smoke test, the fixture repositories and the fake store servers (`tool/e2e/fake_stores`, one package each: App Store Connect, Firebase, Google Play). |
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
- `xp` uses `xp_client` for everything it asks of the engine, and `xp_secrets` to keep its tokens. `xp runner` also
  uses the engine's step runner and the adapters, since it runs jobs.
- `xpd` wires the engine, the adapters and the secret stores. Its tests also run the shipped `xp_client` against it.
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

- `xpd serve [--host 127.0.0.1] [--port 7480] [--data-dir <path>] [--slots <n>]` listens on loopback by default.
  Any other `--host` exposes the engine to the network without encryption, and prints a warning.
  SIGINT and SIGTERM close the server and its WebSocket connections cleanly. `--slots` is how many jobs run at
  once here (see Workflows and the scheduler).
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
adds the tool versions of a job; version 5 adds the time and a unique path to `artifact`; version 6 adds
`shorebird_release`, the Flutter version each Shorebird release was built with; version 7 gives `test_run` its
project, app, time and the baseline index; version 8 gives `credential_ref` the result of its last check and
one credential per flavor and kind; version 9 adds `run` and gives `job` its run, stage, name and capabilities;
version 10 gives `approval` its run, job, decision and expiry; version 11 gives `release` its flavor, branch, pull request,
builds and the status in each store; version 12 adds `housekeeping_setting`; version 13 gives `runner` its credential,
what it reported and when it was revoked, and adds `pairing_token`; version 14 replaces `credential_ref` with the
named `credential` and `credential_assignment` (see Credentials, ADR 0013).

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

## Running as a service

The engine and a runner are meant to run all the time, under the service manager of the machine: a LaunchAgent on
macOS, a systemd unit on Linux. The commands only write the file and call `launchctl` or `systemctl` through the
`ProcessRunner` port (`packages/xp_adapters/lib/src/service`).

```sh
xpd install-service [--data-dir <dir>] [--host ...] [--port ...] [--slots ...]   # then: xpd service-status, xpd uninstall-service
xp runner install-service [--slots 4]                                           # then: xp runner service-status, xp runner uninstall-service
```

- **macOS: LaunchAgents** (D-10, ADR 0005). `~/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist` for the engine and
  `ly.abdurahman.xpath.runner.plist` for a runner, loaded with `launchctl bootstrap gui/<uid>` (and `bootout` to
  unload). A LaunchAgent belongs to the login session of the user: the Mac mini of D-10 logs in on its own (an
  auto-login user), and so the engine can reach the login Keychain; a locked Keychain is "secrets locked", the
  engine never prompts. `RunAtLoad` starts it at login; `KeepAlive` with `SuccessfulExit` false starts it again after
  a crash or a restart request, not after a clean exit (a drain, a stop), with a throttle of 10 s. The plist sets a
  `PATH` that finds what launchd's own does not: `/opt/homebrew/bin`, `/usr/local/bin`, `~/.shorebird/bin`,
  `~/.pub-cache/bin`, `~/fvm/default/bin` and the system directories (`--path` replaces it). Output goes to
  `<data dir>/service-logs/xpd.out.log` and `.err.log` (`runner.*` for a runner); launchd does not rotate them.
  **Who owns the label.** The XPath app registers the bundled `xpd` under the same label with `SMAppService`
  (Phase 15); with the app installed the app owns the service and `xpd install-service` is not needed. The command
  is the way to run the engine without the app (a headless Mac mini, a Mac with the CLI only). It reads
  `launchctl print` first and refuses to replace a label that another registration owns, naming it; `--force` takes
  it over. `SMAppService` keeps its own record of the app's agent, apart from launchd: after a `launchctl bootout`
  (older Homebrew casks did that on upgrade) it still reads "enabled" while launchd has no job, `launchctl
  kickstart` finds nothing and `launchctl bootstrap` of the plist fails (`Bootstrap failed: 5`: a `BundleProgram`
  job has to come from `SMAppService`). The app repairs that itself: when the engine on this Mac does not answer, it
  unregisters and registers the agent again from the running bundle (which also fixes a registration that names a
  moved or replaced copy of the app). It tries once on its own; the banner and Settings ▸ About offer **Start
  engine** (see The desktop app).
- **Linux: systemd.** A user unit by default, `~/.config/systemd/user/xpd.service` and `xp-runner.service`, enabled
  and started with `systemctl --user daemon-reload` and `enable --now`; `--system --run-as <user>` writes a system
  unit in `/etc/systemd/system` that runs as that user (run it as root). A user service stops when the user logs out;
  the command says so and names the fix, `sudo loginctl enable-linger <user>`, when the user does not linger.
  `Restart=on-failure` starts it after a crash or a restart request and not after a clean exit; the unit of a runner
  adds `RestartPreventExitStatus=77 73 78` (revoked, replaced, not paired: starting again would not help).
  `KillMode=mixed` sends the stop signal to the main process (the runner drains, the engine shuts down) and kills the
  steps that are left when `TimeoutStopSec` ran out: 30 s for the engine, 600 s for a runner.
- **The master key (D-07).** `--master-key-credential <file>` writes
  `LoadCredentialEncrypted=xpath-master-key:<file>`; `--master-key-credential-plain <file>` writes
  `LoadCredential=xpath-master-key:<file>`. systemd then puts the key in `$CREDENTIALS_DIRECTORY/xpath-master-key`,
  where the secret store reads it, instead of a `master.key` file in the data directory. Make the file with
  `head -c 32 /dev/urandom | systemd-creds encrypt --name=xpath-master-key - xpath-master-key.cred` (see
  <https://systemd.io/CREDENTIALS/>; `--user` for a user unit on systemd 256 or newer). Do this before the first
  secret is stored: a key that changes later does not open the file. A runner has to be paired with the same key
  (`systemd-run --user -p LoadCredentialEncrypted=xpath-master-key:<file> xp runner pair ...`).
- **The runner service runs `<data dir>/current/bin/xp`.** `xp runner install-service` needs a paired runner and an
  `xp` that runs from an installed bundle (`bin/xp` and `lib/`): it copies that bundle to
  `versions/<version>/`, points `current` at it, and writes a service that starts `current/bin/xp runner start`
  with `XP_RUNNER_MANAGED=1`. That is what lets the runner update itself in place (see Runner updates). It must be
  run from the `xp` that is to run.
- **The files that ship.** `tool/release/linux/xpd.service` and `xp-runner.service` are the reference units for the
  packaging of a release (Phase 18a): user units under `%h`. They are what the Dart templates
  (`renderSystemdUnit`) make of `XpdService.reference` and `RunnerServiceDefinition.reference`; a test fails when
  either file differs, and says how to write it again. The commands render from the same templates with the real
  paths.
- **Engine updates** are not done here: the engine updates only when idle and backs up its database before it
  migrates (D-24); that is the app's job (Phase 18c, Sparkle). Runners follow the engine (Runner updates).
- **Tests.** The managers, the templates and the commands are unit tests with a fake `ProcessRunner` and temporary
  folders: no test installs a LaunchAgent or a unit, or calls `launchctl` or `systemctl`.

## Releases and installation

**Installing.** On a Mac, the notarized app from Homebrew (the tap
[AbdurahmanAlmehdi/homebrew-tap](https://github.com/AbdurahmanAlmehdi/homebrew-tap); Homebrew asks you to trust a
third-party tap once):

```sh
brew trust abdurahmanalmehdi/tap
brew install --cask abdurahmanalmehdi/tap/xpath   # --adopt takes over an XPath.app installed from the DMG
brew upgrade --cask xpath                         # later releases
```

or `XPath-<version>.dmg` from the [latest release](https://github.com/AbdurahmanAlmehdi/x-path/releases/latest). On
Linux, `curl -fsSL https://xpath.abdurahman.ly/install | sh`; or the Docker image below. The rest of this section is
how those are built.

`tool/release/bundles.sh` builds a release of XPath into `build/release` (D-23, ADR 0001):

- **Bundles.** `dart build cli` of `xpd` and `xp` for each target in `bundles/<target>/{xpd,xp}` (`bin/`, `lib/` with
  `libsqlite3`). The targets are `macos-arm64`, `macos-x64`, `linux-x64` and `linux-arm64`; by default every target
  the machine can build. `dart build cli` cross-compiles to Linux from anywhere but builds macOS only for the
  machine's own architecture, so an Apple silicon Mac builds `macos-arm64`, `linux-x64` and `linux-arm64`, and
  `macos-x64` needs an Intel Mac. The host's bundles must print the version of `apps/xpd/pubspec.yaml` (`xp` and
  `xpd` must agree); the others are checked with `file`.
- **Runner bundles.** `runners/<os>-<arch>/xp.tar.gz` (top level `bin` and `lib`), named as a runner reports itself
  (`linux-x86_64`, `linux-arm64`, `macos-arm64`), and copied into `bundles/<target>/xpd/runners/`, where the engine
  serves them to runners that update (Runner updates).
- **Assets.** `assets/xpath-<target>.tar.gz` (top folder `xpath-<version>-<target>/` with `VERSION`, `LICENSE`,
  `install.sh`, `xpd/` and `xp/`), `assets/xp-<target>.tar.gz` (the CLI alone), a `.sha256` for each and
  `install.sh`. The archives hold plain files owned by root, without macOS extended attributes.

**The release workflow** (`.github/workflows/release.yml`) publishes a release on every push to `main`, so on every
merged pull request. Nothing is committed to `main`: the version lives in the tag.

- **Version** (job `version`). `dart run tool/release_version.dart next` decides it. A `vX.Y.Z` tag already on the
  commit is reused (a run again). Otherwise the highest `vX.Y.Z` tag reachable from the commit is bumped by the
  [Conventional Commits](https://www.conventionalcommits.org) titles of the first-parent commits since it: the squash
  commit of each merge, whose title is the pull request title (for a merge commit, the pull request title in its
  body). A breaking change (`feat!:`, `fix(scope)!:` or a `BREAKING CHANGE:` footer) is minor before 1.0 and major
  after, `feat:` is minor and everything else is patch, as in the table of CONTRIBUTING.md. When merges queue up,
  GitHub runs only the newest waiting run, and the largest bump since the last tag wins. Without a tag the base is the
  version of `apps/xpd/pubspec.yaml` (0.0.1) and only the pushed commit decides. Pre-release tags (`v1.0.0-rc.1`)
  are never a base. The build number is the number of commits up to the released one (`git rev-list --count`), so
  it only grows on `main`.
- **Build** (jobs `bundles`, `arm64`, `docker`). `dart run tool/release_version.dart apply <version> <build>` writes
  the version into the build checkout only: the `version` of `apps/xpd` and `apps/xp`, `<version>+<build>` in
  `apps/xp_desktop` (the app's `CFBundleShortVersionString` and `CFBundleVersion`), and the `packageVersion`
  constants that `xpd --version` and `xp --version` print. The pubspecs in git stay at 0.0.1. Then it builds the
  Linux targets (`bundles.sh` checks that `xpd` and `xp` print the version), runs `smoke_bundle.sh` and the
  `install.sh` test, runs the arm64 bundles on an arm64 runner, builds the Docker image, tests that it answers
  `/health` and prints the version, and pushes it to `ghcr.io/abdurahmanalmehdi/xpath:<version>` for `linux/amd64`
  and `linux/arm64` (and `latest` for a release that is not a pre-release).
- **Release** (job `release`). `gh release create` tags the commit `v<version>` through the API (nothing is pushed)
  and publishes the GitHub Release with generated notes and the assets. Every version before 1.0, and every version
  with a `-`, is a pre-release. A run again for a commit that has its release replaces the assets.
- **DMG** (job `dmg`). On a public repository with the signing secrets below, a GitHub-hosted macOS runner writes the
  version the same way, runs `tool/release/build_mac.sh --developer-id --dmg --notarize --upload v<version>` and
  uploads the macOS archives (`xpath-macos-arm64.tar.gz`, `xp-macos-arm64.tar.gz` and their `.sha256`) to the same
  release. Without the secrets it skips itself with a notice; on a private repository it does not run, and the
  macOS archives come from a Mac: `dart run tool/release_version.dart apply <version> <build>`,
  `tool/release/bundles.sh --upload v<version>`, then `git checkout -- apps` to drop the version again.
- **By hand.** A tag `vX.Y.Z` pushed by hand releases that version (1.0 is tagged by hand). Actions ▸ release ▸ Run
  workflow on `main` runs again for its HEAD, optionally with the version to release. A release never comes from
  another branch.

**Signing secrets.** The `dmg` job reads five repository secrets and never prints them. It imports the certificate
into a keychain of its own in the runner's temporary folder, writes the API key there (mode 0600), and deletes the
keychain and both files at the end, also when a step failed. Set each with `gh secret set <name>`, which reads the
value from stdin, or under Settings ▸ Secrets and variables ▸ Actions:

| Secret | What it holds | How to make it |
|---|---|---|
| `MAC_DEVELOPER_ID_P12_BASE64` | The "Developer ID Application: … (AFBD5TBR5U)" certificate and its private key, a `.p12`, in base64. | Create it in Xcode ▸ Settings ▸ Accounts ▸ the team ▸ Manage Certificates… ▸ + ▸ Developer ID Application (the Account Holder only). Export it with its key from Keychain Access ▸ My Certificates as a `.p12` with a password: `base64 -i developer-id.p12 \| gh secret set MAC_DEVELOPER_ID_P12_BASE64`. Delete the `.p12` afterwards. |
| `MAC_DEVELOPER_ID_P12_PASSWORD` | The password of that `.p12`. | The one chosen on export. |
| `MAC_NOTARY_KEY_P8_BASE64` | An App Store Connect API key (`AuthKey_<key id>.p8`) in base64, for `notarytool`. | App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API ▸ Team Keys ▸ +, access Developer. The `.p8` downloads once: `base64 -i AuthKey_<key id>.p8 \| gh secret set MAC_NOTARY_KEY_P8_BASE64`. |
| `MAC_NOTARY_KEY_ID` | The key ID of that key. | Shown in its row. |
| `MAC_NOTARY_ISSUER_ID` | The issuer ID of the team's keys. | Shown above the list of keys. |

**Linux install.** `tool/release/linux/install.sh` is served at `https://xpath.abdurahman.ly/install` (ADR 0005):

```sh
curl -fsSL https://xpath.abdurahman.ly/install | sh                  # engine and CLI, xpd user service
curl -fsSL https://xpath.abdurahman.ly/install | sh -s -- --runner   # a runner machine: pair it afterwards
```

It downloads `xpath-linux-<arch>.tar.gz` of the latest release (`--version` for another) from GitHub Releases and
refuses it when the SHA-256 does not match its `.sha256` (GitHub's latest release is never a pre-release, so before 1.0
it needs `--version`); `--archive` installs a local archive or unpacked folder
instead, and the `install.sh` inside an unpacked release folder installs that folder. The bundles go to
`<prefix>/lib/xpath/{xpd,xp}` (`--prefix`, default `~/.local`) and `<prefix>/bin/xpd` and `xp` link to them. They
are copied beside the old ones and must start (`--version`, so a wrong architecture or C library stops the install)
before they replace them, so running it again updates in place. With a systemd user session it then runs
`xpd install-service` (the `xpd.service` user unit of Running as a service) and restarts the service when it was
installed already; without one it says how to start the engine. The unit it writes has no master key credential, so
the engine keeps a 0600 `master.key` in its data directory (D-07); for a systemd credential run `xpd install-service
--master-key-credential <file>` yourself before the first secret is stored. `--runner` prints `xp runner pair` and
`xp runner install-service`, which writes `xp-runner.service` once the runner is paired. `--no-service` installs the
files only. Each option has an environment variable (`XPATH_VERSION`, `XPATH_PREFIX`, `XPATH_ARCHIVE`,
`XPATH_RUNNER=1`, `XPATH_NO_SERVICE=1`); `XPATH_RELEASES_URL` replaces the GitHub Releases URL.
`tool/release/linux/install_test.sh` tests it with no network against the archive of the machine in
`build/release/assets`, in a throwaway `HOME` and prefix: an install, an update from the unpacked folder, a download
from `file://` URLs with and without a version, a wrong SHA-256, a wrong version and the runner mode; on Linux also
the service step against a fake `systemctl` and `loginctl` (the unit written, `enable --now`, the restart on update)
and `--with-android` against a fake `apt-get`, `sudo`, `dpkg-query` and `sdkmanager`.

**Which versions work together** (runners follow their engine; the app and the CLI need the same API version):
[docs/guide/install.md](docs/guide/install.md#which-versions-work-together).

**A Linux runner, with Android.** `install.sh --runner --with-android` (Debian or Ubuntu) also installs a JDK 17, git,
ssh, curl, unzip, xz, zip and perl with `apt-get`, the Android command-line tools (pinned by version and SHA-256),
the licences, one platform and one build-tools, into `--android-sdk <dir>` (default `~/Android/Sdk`, where Flutter
looks). It ends with the next steps: `xp runner doctor`, the pairing command, `xp runner install-service`.

**Docker.** The `Dockerfile` copies the Linux bundles of `build/release/bundles` (run `bundles.sh` first; `buildx`
picks the bundle of each platform) into a `debian:trixie-slim` image with `git`, `ssh` and `curl`, but not `unzip`,
which the Flutter SDK download needs, so the engine's own runner offers no `flutter` and builds go to runners. It runs `xpd serve --host 0.0.0.0 --port 7480` as the user `xpath` (uid 10001), keeps its
data (database, `master.key`) in the volume `/data` (`XPATH_DATA_DIR`) and checks `/health` every 30 s.

```sh
tool/release/bundles.sh && docker build -t xpath .
docker run -d --name xpath -p 127.0.0.1:7480:7480 -v xpath-data:/data xpath
docker exec xpath xpd token create --name laptop --kind cli
```

**The runner image.** `Dockerfile.runner` makes `ghcr.io/abdurahmanalmehdi/xpath-runner`, a runner that offers
`android` and `flutter` out of the box (amd64 only): it is built by `install.sh --runner --with-android` from the
release archive, and the release workflow checks `xp runner doctor` in it before it pushes it. How to run it:
[docs/guide/runners.md](docs/guide/runners.md#the-runner-image).

**The Mac app (local install, Phase 18b).** `tool/release/build_mac.sh` builds `dist/XPath.app` (gitignored) for
this Mac: it runs `bundles.sh` for the Mac's target and the Linux runner targets (`--reuse-bundles` takes the ones in
`build/release`), `flutter build macos --release`, copies the `xpd` and `xp` bundles (`bin/`, `lib/`) into
`Contents/Helpers/xpd` and `Contents/Helpers/xp` (the LaunchAgent plist runs `Contents/Helpers/xpd/bin/xpd`, the app
links `Contents/Helpers/xp/bin/xp`) and the runner archives into `Contents/Resources/runners` (Helpers may hold only
code; the engine looks there when it runs from the app). It then signs every Mach-O inside, deepest first, then the
frameworks, then the app with `Release.entitlements`, all with the Hardened Runtime (`--options runtime`) and
`--timestamp=none`, verifies with `codesign --verify --deep --strict` and runs the signed helpers' `--version`. The
helpers are signed with `apps/xp_desktop/macos/Runner/Helpers.entitlements`: the Dart AOT runtime maps its snapshot
as executable memory, and the Hardened Runtime kills it at start (exit 137) without
`com.apple.security.cs.allow-unsigned-executable-memory`. `libsqlite3` needs nothing: it is signed by the same team,
so library validation passes. `spctl` rejects the app (Gatekeeper accepts only Developer ID outside the App Store),
which does not matter for a build that never carried a quarantine flag. The identity is `$XPATH_SIGN_IDENTITY`, by default the owner's Apple Development certificate (SHA-1
`3B9E9C2FB4D94EFC7AC367C68CF1FC077EBB799F`, team AFBD5TBR5U); a `codesign` that waits more than 60 s (a Keychain
dialog) is stopped. `--install` then quits a running XPath (SIGTERM, no Apple Event), replaces
`/Applications/XPath.app` and makes LaunchServices forget the build-folder copies
(`apps/xp_desktop/build/macos/Build/Products/*/XPath.app`, `dist/XPath.app`; `lsregister -u`) and register the
installed one (`lsregister -f`): they share the bundle id, so macOS could otherwise open a Debug build, whose
LaunchAgent points at a bundle without `xpd` (launchd `EX_CONFIG`). Nothing else: it does not open the app, register
the LaunchAgent or link `xp` (onboarding or Settings ▸ Command line tool does). A running
engine keeps the old `xpd` until it restarts (`launchctl kickstart -k gui/$(id -u)/ly.abdurahman.xpath.xpd`). The
macOS 26 `.icon` (Icon Composer) is manual; the app uses `docs/design/brand/macos/AppIcon.appiconset`.

**The Mac download (DMG).** The same script builds what the release workflow publishes. The app's version
(`CFBundleShortVersionString`) and the bundled `xpd` and `xp` must all print the version of `apps/xpd/pubspec.yaml`
(`dart run tool/release_version.dart apply <version> <build>` writes it), and the script checks that before and
after the build:

- `--developer-id` signs with a "Developer ID Application: … (AFBD5TBR5U)" identity instead (the team is
  `$XPATH_TEAM_ID`), with a secure timestamp (`--timestamp`, which needs the network) and the Hardened Runtime. It
  is the one such identity in the keychain, or the one `$XPATH_SIGN_IDENTITY` names; an Apple Distribution or Apple
  Development identity is refused. Without one it stops before building and says how to create it: Xcode ▸
  Settings ▸ Accounts ▸ the team ▸ Manage Certificates… ▸ + ▸ Developer ID Application (only the Account Holder can).
- `--dmg` builds `dist/XPath-<version>.dmg` (the app and a link to `/Applications`), signs it with the same identity,
  mounts it and checks the signed app and the link inside. Without `--developer-id` it is signed with Apple
  Development and says that it is for this Mac only, not for distribution.
- `--notarize` (needs `--developer-id`) submits the app to Apple's notary service with
  `xcrun notarytool submit --wait` and staples it, then the DMG (with `--dmg`) and staples it too, and runs
  `spctl -a -vv -t install` on the DMG, which must report "source=Notarized Developer ID". The credentials are a
  `notarytool store-credentials` keychain profile in `$XPATH_NOTARY_PROFILE`, or an App Store Connect API key:
  `$XPATH_NOTARY_KEY` (the `.p8` file), `$XPATH_NOTARY_KEY_ID` and `$XPATH_NOTARY_ISSUER`. A rejected submission
  prints its log.
- `--upload v<version>` (needs `--dmg` and `--notarize`) attaches the DMG to the existing GitHub Release
  (`gh release upload --clobber`); the tag must be `v<version>`.

```sh
tool/release/build_mac.sh --reuse-bundles --dmg                    # local DMG, Apple Development
XPATH_NOTARY_PROFILE=xpath tool/release/build_mac.sh --developer-id --dmg --notarize
```

**The engine under the app's LaunchAgent.** The plist sets `XPATH_LAUNCHD=1`. `xpd serve` then writes its output,
each line stamped with the UTC time, to `<data dir>/service-logs/xpd.log` (moved to `xpd.log.1` past 10 MB at a
start). Whoever starts it, `xpd serve` puts the tool folders that exist and are missing from its `PATH` in front of
it: `~/.shorebird/bin`, `~/.pub-cache/bin`, `~/fvm/default/bin`, `/opt/homebrew/bin`, `/usr/local/bin` (a plist
cannot name the home folder). The jobs, the tool probes and every program the engine runs get that `PATH`.

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

## App Store Connect and Apple

Phase 10a adds the Apple side of the stores (D-14): the App Store Connect REST client, the iTunes lookup,
`upload.appStore` and the two guard checks that ask Apple. Interfaces and the parser are in
`packages/xp_engine/lib/src/stores/apple`, the HTTP adapters in `packages/xp_adapters/lib/src/stores/apple`.
Nothing here calls Apple in a test: the adapters run against `tool/e2e/fake_stores/asc` (below) and altool is
only ever faked or read from captured output.

- **The ASC API key is one secret.** The `secret_key` of an `asc_key` credential names a secret in the
  secret store whose value is JSON (`AscKey.toSecret`):
  `{"keyId": "ABC123DEF4", "issuerId": "<uuid>", "keyKind": "team" | "individual", "privateKey": "<.p8 text>"}`.
  `keyKind` defaults to `team`. The credential endpoints (see Credentials) write it. An Apple ID flavor has an
  `apple_id` credential instead, and no REST access.
- **Tokens** (`AscTokenProvider`) are ES256 JWTs signed in pure Dart (`pointycastle`, RFC 6979 nonces, raw
  `r || s`): header `alg`, `kid`, `typ`; claims `iat`, `exp` (15 minutes, Apple's maximum is 20), `aud:
  appstoreconnect-v1`, and `iss` for a team key or `sub: user` with no `iss` for an individual key. One token is
  kept until two minutes before it expires. The signer is checked against the RFC 6979 test vector, against
  `openssl dgst -verify` (`process` tag), and the fake server verifies the tokens it receives like Apple does.
- **The REST client** (`HttpAppStoreConnect`) reads apps by bundle id, builds (by app, marketing version and build
  number, with their processing state), App Store versions with **`appVersionState`** (`appStoreState` is
  deprecated and never read), review submissions (create with the version, submit, read) and phased releases
  (read, pause, resume, complete). Lists follow `links.next`, but only to the host of the base URL: the token is
  never sent anywhere else. Errors are typed by status (`AscAuthException` 401, `AscForbiddenException` 403,
  `AscNotFoundException` 404, `AscConflictException` 409, `AscValidationException` 422,
  `AscRateLimitedException` 429, `AscServerException` otherwise), each with Apple's message and code and a fix.
  A `429` is waited out when Apple's `Retry-After` (else 1 s, 2 s, ... backoff) is at most 30 s, up to three
  attempts; a longer wait (the hourly quota is spent) is thrown at once with `retryAfter`, because a job must not
  sleep for an hour. A `5xx` on a read is retried the same way. The quota left comes from `X-Rate-Limit` after
  each answer (`rateLimit`).
- **The iTunes lookup** (`HttpItunesLookup`) asks `itunes.apple.com/lookup` for the app's own storefront
  (`store_country` of the profile) with a changing `_` parameter to get past Apple's CDN. It needs no key, so it
  is the only Apple source for an Apple ID flavor. It is "live somewhere", not precise.
- **`AppStoreTrains`** (the `appStoreTrain` guard check, ITMS-90186) takes the live version from the iTunes lookup
  and, with an API key, from `appVersionState` too; the versions that are approved and not live yet
  (`PENDING_DEVELOPER_RELEASE`, `PENDING_APPLE_RELEASE`, `PROCESSING_FOR_APP_STORE`, ...) are the closed trains.
  **`StoreBuildNumbers`** (the `buildNumberReuse` guard check) is every build number App Store Connect has for the
  app, expired builds included; it needs an API key, and answers for iOS only (Google Play's half is in the next section).
  `SqliteAscCredentialSource` finds the key through the `asc_key` credential assigned to the flavor with the bundle id.
  `xpd serve` wires all of it in `apps/xpd/lib/src/stores/apple_stores.dart`; the `appStoreTrain` check and the
  step are registered there, and `buildNumberReuse` over both stores' numbers in `store_guard_checks.dart`.
- **`upload.appStore`** (side effect, always on the engine, D-09; ADR 0014). With an API key (`asc_key`) it
  uploads through the App Store Connect build-upload API on any engine, a Linux or Docker one included:
  `POST /v1/buildUploads`, `POST /v1/buildUploadFiles`, a `PUT` of each part of the IPA to the address Apple
  names (without the token, and never quoted in an error, since the address is signed), `PATCH` the file
  uploaded with its MD5, then it polls the upload until App Store Connect accepts or refuses it, for at most
  30 minutes. A refusal is told the way altool's are (`AltoolOutput.ofUploadErrors`, with the same fixes);
  an upload still undecided fails with "resume the step later", and the resumed step finds the build if Apple
  made one. The IPA must still have the SHA-256 recorded for it. With an Apple ID it runs, on macOS only,
  `xcrun altool --upload-package <ipa> --type ios --apple-id <id> --bundle-id <id> --bundle-version <build>
  --bundle-short-version-string <version> -u <apple id> -p @env:XPATH_ASC_APP_PASSWORD`, so the app-specific
  password is in the environment of altool only, masked in the log, never in `ps`. Only that case needs
  `ios-sign`.
- **altool's output decides, not its exit code** (`AltoolOutput`, Apple ID uploads). altool can exit 0 after Apple rejected the
  build (a closed version train, for example). The step fails on any line with `ERROR:`, `ERROR ITMS-`, `*** Error:`,
  `validation failed`, `upload failed`, `VALIDATION_ERROR`, `failed to upload|validate package` or `unable to
  authenticate`, and tells the first three. Known codes get a fix: 90186 and 90062 (bump the version), 90189
  (allocate a new build number), authentication. A success line (`UPLOAD SUCCEEDED`, `No errors uploading`,
  `upload complete`) and altool's delivery UUID are recorded when present; an output with neither errors nor
  success is a success that is not `confirmed`, as in the reference scripts. The fixtures are in
  `packages/xp_engine/test/src/stores/apple/fixtures` (its README says which are captured from altool 27.0.5
  and which are reconstructed).
- **`alreadyDone`** asks whether App Store Connect has the build: the builds API for an API key (by app,
  version and build number); for an Apple ID `altool --build-status`, which counts only if its output names the
  build number. When it cannot ask, the step runs, and Apple refuses a build number it has seen.

### Fake App Store Connect

`tool/e2e/fake_stores/asc` is the workspace package `xp_fake_asc`: a `dart:io` server on a loopback port
(`FakeAscServer.start`) with apps, builds, App Store versions, review submissions, phased releases and the iTunes
lookup in memory, in JSON:API shape. It verifies every bearer token (signature with the registered public key,
`kid`, `aud`, `exp`, at most 20 minutes, `iss` or `sub` per key kind) and says what is wrong in the 401. Tests fill
it with `addApp`, `addBuild`, `addVersion`, `addPhasedRelease` and `addItunes`, make it misbehave with
`failNext` and `rateLimitNext`, and read `requests`. The test key (`fakeAscTestKey`, made with `openssl`) signs
nothing real. `release_e2e.sh` (Phases 11 and 12b) will reuse it. The layer rules let `xp_adapters` and `xpd` use it
(as a dev dependency).

## Google Play

Phase 10b adds the Google Play side of the stores (D-15): the Developer API client, `upload.play`, the Play half
of the `buildNumberReuse` guard check and the `playTargetSdk` guard check. Interfaces are in
`packages/xp_engine/lib/src/stores/play`, the HTTP adapters in `packages/xp_adapters/lib/src/stores/play`. Nothing
here calls Google in a test: the adapters run against `tool/e2e/fake_stores/play` (below).

- **The service account is one secret.** The `secret_key` of a `play_sa` credential names a secret in the
  secret store whose value is the JSON key file Google Cloud gives out, as it is (`PlayServiceAccount`): it needs
  `client_email` and `private_key`, uses `token_uri` (default `https://oauth2.googleapis.com/token`) and
  `private_key_id`, and ignores the rest. The credential endpoints (see Credentials) write it. A flavor with no
  `play_sa` credential assigned has no service account: XPath cannot upload for it, `upload.play` fails with "upload the
  bundle by hand", and the build numbers of Play are unknown (the endpoint behind "Play: live" is Phase 12b, the desktop's button Phase 16b).
  Setting up the account: enable the Google Play Android Developer API in the Cloud project, create the service
  account and a JSON key, and invite its email in the Play Console (Users and permissions) with permission to
  release the app.
- **Auth is the OAuth2 JWT bearer flow, in pure Dart** (`PlayTokenProvider`, `Rs256Signer`). The assertion is an
  RS256 JWT (header `alg`, `typ`, `kid`; claims `iss` the service account email, `scope`
  `https://www.googleapis.com/auth/androidpublisher`, `aud` the `token_uri`, `iat`, `exp` 30 minutes later; Google's
  maximum is an hour) posted as `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`. The access token is kept
  until two minutes before it expires; calls that overlap share one request; a `401` drops the token and the call
  is tried once more with a new one. **Why `pointycastle` and not `googleapis_auth`:** `googleapis_auth` hardcodes
  the token endpoint, so the fake server could not stand in for it; the `token_uri` of the key file is the one
  address the flow needs, and the signer is 30 lines on a package already used for ES256 (Phase 10a). The signer is
  checked byte for byte against `openssl dgst -sha256 -sign`, and against `openssl dgst -verify` (`process` tag).
- **The Developer API client** (`HttpGooglePlay`, `package:http`, base URLs of the API and of the upload host
  injectable) does `edits.insert`, `edits.delete`, `edits.bundles.upload` and `list`, `edits.tracks.get` and
  `update`, `edits.commit` and `tracks.releases.list`. Bundles go up with the simple media upload
  (`uploadType=media`), **streamed from the artifact store with a known length**, never held in memory; the stream
  is opened again if the upload has to be repeated. Errors are typed, each with Google's message, reason and a fix:
  `PlayAuthException` (401, or the token endpoint), `PlayForbiddenException` (403: invite the service account),
  `PlayNotFoundException` (404), `PlayVersionCodeUsedException` (a version code seen before),
  `PlayConflictException` (409), `PlayValidationException` (other 4xx), `PlayRateLimitedException` (429),
  `PlayServerException`. A `429` is waited out when `Retry-After` (else 1 s, 2 s, ...) is at most 30 s, up to three
  attempts; a longer wait is thrown at once with `retryAfter`. A `5xx` is retried for reads, track updates and
  deletes; **not for an upload or a commit**, which may have gone through: `alreadyDone` finds out.
- **A review in progress is never cancelled.** `GooglePlay.commitEdit` has no option: it always sends
  `changesInReviewBehavior=ERROR_IF_IN_REVIEW` (`edits.commit` defaults to cancelling the review). When changes
  are in review Google answers `400 FAILED_PRECONDITION` with `CHANGES_ALREADY_IN_REVIEW`, the edit stays valid and
  the review is untouched; the client throws `PlayReviewInProgressException`. The fake server implements both
  behaviors and records the parameter and any cancelled review, so the acceptance test asserts the parameter was
  sent and the review survived (`http_google_play_test.dart`, "while a review is in progress fails without
  cancelling it").
- **`upload.play`** (side effect, always on the engine, D-09) streams the AAB of the job (it must still have the
  SHA-256 recorded for it), opens an edit, uploads, checks that the bundle's version code is the build number of
  the input, sets the release of the track and commits. Input: `artifactName`, `packageName`, `version`
  (`x.y.z+build`, the build is the version code), `serviceAccountSecret`, and optionally `track` (default
  `internal`), `status` (`completed` by default, `inProgress` with a `userFraction` above 0 and below 1, or
  `draft`), `releaseName` and `releaseNotes` (language tag to text). Whatever fails after the edit was opened, the
  edit is deleted, so nothing is left half done. A review in progress fails the step with "Play has a review in
  progress; the release was not committed and the review was not cancelled". The result carries the version code,
  the track and the `releaseLifecycleState` of the new release when Play can say.
- **`alreadyDone`** lists the releases of the track (`tracks.releases.list`: committed releases, at most 20, no edit
  needed, state `DRAFT`, `NOT_SENT_FOR_REVIEW`, `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, `NOT_APPROVED` or
  `PUBLISHED`) and is done when one holds the version code. Google's `googleapis` Dart package has no
  `tracks.releases.list`, which is one more reason the client is hand-written against the REST shapes in the
  discovery document.
- **Build numbers.** `PlayStoreBuildNumbers` reads every bundle of the app (`edits.bundles.list` in a short edit
  that is deleted again): Play refuses a version code it has seen on any track. It needs a service account and
  covers bundles only (XPath uploads bundles). `CombinedStoreBuildNumbers` asks App Store Connect for the iOS
  bundle id and Play for the Android application id, adds the numbers up and names a store it could not read in
  `StoreBuilds.unreadable`; `buildNumberReuse` then warns instead of passing, but still fails for a number the
  other store has. `xpd serve` composes it in `apps/xpd/lib/src/stores/store_guard_checks.dart`.
- **`playTargetSdk`** compares the `targetSdk` in the Gradle scripts with the level Play asks for. Google publishes
  no API for that policy value, so it is a setting (`ConfiguredPlayRequirements`): the default is **36**, what Play
  has asked of new apps and updates since 2026-08-31 (Android 16). Play raises it every August; set
  `XPD_PLAY_TARGET_SDK` for `xpd serve` (a whole number from 21 to 99; anything else stops the engine at start).

### Fake Google Play

`tool/e2e/fake_stores/play` is the workspace package `xp_fake_play`: a `dart:io` server on a loopback port
(`FakePlayServer.start`) that is both the OAuth2 token endpoint (`/token`) and the Developer API. It verifies the
signed assertion like Google does (RS256 against the public key of the registered account, `iss`, `scope`, `aud`
the token endpoint, `exp`, at most an hour) and says what is wrong in the `invalid_grant`; it issues access tokens
that expire by the fake clock and checks one on every API call. `serviceAccountJson()` makes the key file for the
test account with `token_uri` pointing at the server. It keeps apps, edits, bundles, tracks and releases in memory,
validates what Play validates (the bundle must be an AAB, a version code is used once, a release can only name
uploaded bundles, `userFraction` only with `inProgress`) and answers with Google's error bodies. A commit while a
release is `IN_REVIEW` answers `400 CHANGES_ALREADY_IN_REVIEW` with `ERROR_IF_IN_REVIEW` and cancels the review
without it; `commits` and `FakePlayApp.cancelledReviews` record which. A test AAB is any bytes that start with
`fake-aab versionCode=<n>` (`fakeAab(n)`), because the fake reads the version code from the first line where Play
reads the manifest. Tests fill it with `addApp` and `FakePlayApp.addRelease`, make it misbehave with `failNext`,
`rateLimitNext` and `revokeTokens`, and read `requests`. The test key (made with `openssl genpkey`) signs nothing
real. The layer rules let `xp_adapters` and `xpd` use it (as a dev dependency).

## Firebase, Shorebird CLI and credentials

Phase 10c adds Firebase App Distribution, the last store adapter (`upload.firebase`, D-16), consolidates the Shorebird
CLI access, and gives the engine the credentials every upload needs: saved after the place they are for accepts them,
checked every day, and checked again before a job builds. Interfaces and verifiers are in
`packages/xp_engine/lib/src/{credentials,stores/firebase}`, the HTTP and CLI adapters in
`packages/xp_adapters/lib/src/{credentials,stores/firebase,stores/shorebird,github,sqlite}`, the endpoints in
`apps/xpd/lib/src/api/credentials`. Nothing here calls Google, Apple, Shorebird or GitHub in a test.

### Firebase App Distribution

- **`upload.firebase`** (side effect, always on the engine, D-09) uploads the APK, AAB or IPA of the job (it must still
  have the SHA-256 recorded for it) with the REST API and a service account: no Node and no `firebase` CLI. Input:
  `artifactName`, `appId` (`1:684690133351:android:...`; the project number the API addresses the app by is its
  second part, so there is no separate field), `version` (`x.y.z+build`), `serviceAccountSecret`, and optionally
  `testerEmails`, `groupAliases` and `releaseNotes`. Steps: `POST
  https://firebaseappdistribution.googleapis.com/upload/v1/projects/{number}/apps/{appId}/releases:upload` with the raw
  bytes streamed from the artifact store with a known length (`X-Goog-Upload-Protocol: raw`,
  `X-Goog-Upload-File-Name`); poll the long-running operation every 3 s until it is done (at most 200 polls);
  `releases.patch` with `updateMask=releaseNotes.text`; `releases:distribute`. Firebase reads the version from the
  binary: if it is not the version of the job the step fails and names the release it made.
- **`alreadyDone`** lists the newest 300 releases (`releases.list`, `orderBy=createTime desc`, three pages of 100) and is
  done when one has the build number and version name of the input and, if the input has release notes, the same
  notes. A release with other notes was not finished (the notes and the distribution come after the upload), so the
  step runs again: the upload finds the same release (`RELEASE_UNMODIFIED` or `RELEASE_UPDATED`) and the rest is
  repeated. A failure after the upload says so and names the release. Known limit: the API shows no testers, so a
  release whose distribution failed but whose notes are set counts as done; a deterministic failure there (a group that
  does not exist) needs a new job anyway.
- **The service account** is the JSON key file, as `firebase_sa` (same convention as `play_sa`). The token is the same
  OAuth2 JWT bearer flow as Google Play (`PlayTokenProvider`, now with a `scope`; Firebase asks for
  `https://www.googleapis.com/auth/cloud-platform`), so `HttpFirebaseAppDistribution` reuses it and maps its failures to
  `FirebaseException`s with a fix (`FirebaseAuthException` 401, `FirebaseForbiddenException` 403 with the role to give,
  `FirebaseNotFoundException`, `FirebaseValidationException`, `FirebaseRateLimitedException`,
  `FirebaseServerException`, `FirebaseOperationFailedException`). Retries are as for Play: a `429` is waited out up to
  30 s; a `5xx` is retried for reads, release notes and distribution, **never for the upload**, which may have gone
  through.
- **The Firebase app id is a step input.** The scanner does not read `google-services.json` or `firebase.json` yet, so
  workflows take it as an input (`firebaseAppIds`, by flavor and platform); nothing here guesses it.

### Fake Firebase App Distribution

`tool/e2e/fake_stores/firebase` is the workspace package `xp_fake_firebase`: a `dart:io` server on a loopback port
(`FakeFirebaseServer.start`) that is both the OAuth2 token endpoint and the REST API. It is a package of its own, not
an extension of the Play fake: the two APIs share nothing but Google's token flow, so `xp_fake_firebase` depends on
`xp_fake_play` for exactly that (`AssertionVerifier`, now with a `scope`, the test account and its key) and the layer
rules allow nothing else. It checks the assertion and the access token like Google does, takes `releases:upload`
(raw protocol and file name header required) and answers with an operation that is done after `pollsBeforeDone`
polls, finds the release of the same version name and build (`RELEASE_UNMODIFIED` when the bytes are the same,
`RELEASE_UPDATED` when not), lists releases newest first in pages, patches the notes, and distributes (a group that was
not added with `addApp(groups:)` is a `400`). A test binary is any bytes that start with `fake-apk versionName=1.2.3
versionCode=45` (`fakeBinary`). Tests fill it with `addApp` and `addRelease` and make it misbehave with `failNext`,
`rateLimitNext` and `revokeTokens`.

### The Shorebird CLI

`ShorebirdCli` (`packages/xp_adapters/lib/src/stores/shorebird`) is the one place the CLI is run: always `CI=true`
(no prompts), JSON in, the API key in `SHOREBIRD_TOKEN` and never in the arguments, a time limit, and the documented
envelope `{"status": "success", "data": ...}` read into a result that is either a success or a failure that says
whether the program is missing, too slow or failed. `ShorebirdCliReleases` (`releases list`, Phase 9c) now goes through
it, and so does `ShorebirdCliVerifier`, which checks an API key with `shorebird account whoami --json`. The
documentation shows the command, not the shape of its JSON, so the verifier only needs the envelope and reads `email`
when it is there (the fixtures are reconstructed from the documentation and say so). A key that does not start with
`sb_api_` is refused without asking Shorebird, with the reason that `login:ci` tokens stopped working on 2026-10-01.

### Credentials

Credentials are the engine's, with names (ADR 0013). A **named credential** (the `credential` table) has an id
(`crd_...`, which never changes), a name that is unique regardless of case ("Personal Apple Dev Account", "Mataa Apple
Dev Account"), a kind, its secret, the `account` it belongs to when that is not secret, and the result of its own check
(does it authenticate). Any flavor of any project may use it: a flavor (an app path and a flavor name, `.` and
`default` for an app without flavors) uses **at most one credential of each kind** (`credential_assignment`, only of
the credential's kind), and each assignment keeps the result of its own check (can the credential reach this
flavor's bundle id, package or app). So one Apple key serves the dev and the prod flavor, and two Shorebird keys are
told apart by name. Renaming a credential or giving it a new secret keeps its id and every assignment. The secret is
only in the secret store, under the `secret_key` of the credential (`credential.<id>`; a secret another credential
keeps is not deleted with this one). Identical secrets under two names stay two credentials.

The GitHub token is not a named credential: the engine has one, under `github.token`, set with `PUT /github-token`
(see GitHub). A `slack` webhook is named and assigned per flavor like the others; a notice of a project goes to the
first webhook a flavor of the project uses and no check refused.

What each kind stores and how it is checked:

| Kind | Secret store | Check of the credential (cheap, changes nothing) | Check of an assignment |
|---|---|---|---|
| `asc_key` | JSON `{keyId, issuerId, keyKind, privateKey}` | `GET /v1/apps?limit=1` with a signed token; a `401` is an expired or revoked key | the key sees the app with the flavor's iOS bundle id (`GET /v1/apps?filter[bundleId]=`) |
| `apple_id` | the app-specific password; the Apple ID is the `account` | `xcrun altool --list-providers -u <id> -p @env:XPATH_ASC_APP_PASSWORD`; a password that is not shaped like `abcd-efgh-ijkl-mnop` is refused unasked | the credential's |
| `play_sa` | the JSON key file | token exchange | `tracks.releases.list` of the internal track of the flavor's application id |
| `firebase_sa` | the JSON key file | token exchange with the `cloud-platform` scope | the credential's (the app ids belong to the steps) |
| `keystore` | the bytes; `<key>.storePassword`, `<key>.keyPassword`; the alias is the `account` | `keytool -list -keystore <0600 temp file> -storepass:env XPATH_KEYSTORE_STOREPASS -alias <alias>` | the credential's |
| `shorebird` | the `sb_api_*` key | `shorebird account whoami --json` with `SHOREBIRD_TOKEN` | the credential's |
| `slack` | the webhook URL | its shape only (`https://hooks.slack.com/services/T/B/X`); no message is sent | the credential's |

A check ends `verified`, `rejected` (the place said no: expired, revoked, wrong password, a missing role, an app the
key cannot see) or `unreachable` (no network, a missing tool: it says nothing about the credential). A kind whose
check does not look at the flavor, and a credential its own check did not accept, gives each assignment the
credential's status. Only `rejected` blocks a job. The keytool check proves the store password and the alias;
`keytool` has no check for the key password. The password of an Apple ID and of a keystore reach the program through
the environment, never the arguments, and every secret value is given to the log masker as soon as it arrives.

Only `app` and `cli` tokens change credentials; an `mcp` token reads them (`403 forbidden` otherwise) and a `runner`
token reaches none of these routes (ADR 0011).

| Route | What it does |
|---|---|
| `GET /credentials` | The named credentials by name, each with `usedBy`: the flavors that use it, with the check of each assignment. No secret is ever returned. |
| `POST /credentials` | `{"name": "...", "kind": "asc_key", ...}` with the secret fields of the kind (`CreateCredentialRequest`; `packages/xp_api/openapi.yaml` has one schema per kind). Verifies, then stores the secret and the credential: `201`. No flavor uses it yet. `409 conflict` for a name that is taken in any case; `422 credential_rejected` says why and how to fix it and **stores nothing**; `502 upstream_error` when the check could not be made, also stores nothing. |
| `GET /credentials/{id}` | One credential with `usedBy`. |
| `PATCH /credentials/{id}` | `{"name": "..."}`: renames it; `409` for a name that is taken. |
| `PUT /credentials/{id}` | The secret fields of its kind: a new secret, checked first (`422`/`502` change nothing). The name and the assignments stay, and the assignments are checked again. |
| `POST /credentials/{id}/verify` | Checks the credential and each assignment now and keeps the results. A refusal is still a `200`, with `status: rejected`. |
| `DELETE /credentials/{id}` | Deletes it and its secret. A credential that flavors use answers `409 credential_in_use` with `usedBy`, and is deleted only with `?force=true`, which unassigns it first. |
| `GET /projects/{id}/credentials` | The credential each flavor of the project uses, by app, flavor and kind: `id`, `name`, `account`, `credentialStatus` (the credential's check), `assignmentStatus` (the assignment's) and `status`, `message`, `fix` as preflight sees them (a refusal of either is a refusal). `?flavor=` (and `?app=`, `.` by default) for one flavor. |
| `PUT /projects/{id}/flavors/{flavor}/credentials/{kind}` | `{"credentialId": "crd_...", "allFlavors": false, "replace": false}`, `?app=` for an app below the root. The flavor uses the credential for the kind from now on; with `allFlavors` every flavor of the app does too, except those that have another credential of the kind: they keep it (`kept` in the answer) unless `replace`. Each assignment is checked at once; a refusal does not undo it, it fails preflight until fixed. |
| `DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}` | The flavor stops using its credential of the kind; the credential stays. |

**Deprecated, kept so that no client breaks:** `PUT /projects/{id}/credentials` takes the per-flavor body of before
(`{"app": ".", "flavor": "prod", "kind": "asc_key", ...}`, optionally with a `name`): the credential is checked as
`POST /credentials` checks it; if the flavor's credential of the kind is used by that flavor alone it gets the new
secret (`200`, same id), otherwise a new named credential is created (`201`) and the flavor uses it, called `name` or
"<kind> · <project> <app> <flavor>". A `github` token there becomes the engine's GitHub token.
`POST /projects/{id}/credentials/{credentialId}/verify` verifies the credential and answers as the first flavor of the
project that uses it sees it, and `DELETE /projects/{id}/credentials/{credentialId}` unassigns it from the project's
flavors and deletes it when no other flavor uses it.

Creating, replacing, renaming, checking, expiring, deleting, assigning and unassigning announce `credential.saved`,
`credential.renamed`, `credential.verified`, `credential.expired` (a credential or an assignment that was `verified`
and is `rejected` now, once), `credential.removed`, `credential.assigned` and `credential.unassigned` on `/events`; the
events carry ids, names, places and kinds, never a secret. The server logs no request, and a failure names the field
that is wrong, not its value.

**The migration** (schema version 14) turns every `credential_ref` row of before into a named credential with the
same id, secret key, account and check, called "<kind> · <project> [<app> ]<flavor>" (for example "App Store Connect
API key · acme/shop prod"; cut to 80 characters, and a name that two rows would share gets the id after it), and an
assignment to its flavor with the same check. Secrets are neither read nor touched, and identical ones are not merged:
rename them, assign one to the flavors and delete the others. The per-flavor `github` rows are dropped: each of them
named the engine's GitHub token (`github.token`, the key they were saved under), which stays the one GitHub token, so
nothing is lost. `xpd` logs what the migration did on stderr (`xpd: Named 5 credential(s) ...`, `xpd: Dropped 2
per-flavor GitHub credential reference(s) ...`), and the database before it is kept as `xpath.db.bak-v13`.

**The daily health check** (`CredentialHealthCheck`, started by `xpd serve`) checks every credential and every
assignment every 24 hours and records the results. When the engine starts it also checks at once if any of them was
last checked more than a day ago, so a Mac mini that was off catches up; this does not delay the engine, which is
listening already. Checks never overlap, and a failed run (locked secrets, say) is reported to stderr and tried again
at the next tick.

**Preflight.** The `credentials` guard check reads the recorded results of the credentials assigned to the flavor named
in the step input (`flavorId`; `credentialKinds` narrows it to what the job needs, and a kind that is listed but not
assigned fails). A credential or an assignment that is `rejected` fails the `guard` step with the reason and the fix,
so the job stops before any build step runs; an `unreachable` or never-checked one is a warning. The acceptance tests
are `credentials_preflight_test.dart` in `xp_engine` (an expired ASC key, a revoked app-specific password and a key
that cannot see the flavor's app, through `JobRunner` with the guard first and a build step that must stay `pending`)
and `credential_checks_test.dart` in `xpd` (the same against the fake ASC server, and one key shared by two flavors).

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
- **Gates** (D-13). `gate: prod_release | prod_patch | store_submission | push | merge | delete` on a step
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
  first preferred. Once Linux iOS builds exist (part 2 of ADR 0014), `build.ios` needs any of `ios-sign`
  and `ios-linux`, and the planner narrows a job Linux cannot build (a flavor, Shorebird iOS, a debug or
  profile build, an app extension, the iOS Simulator) to `ios-sign` with the reasons (`iosLinuxLimits`),
  which its queue message repeats; with no paired runner that offers `ios-sign` the dispatch fails. A
  workflow cannot name `ios-linux` yet.

### Built-in workflows and versions

Every project gets `dev-build`, `prod-release`, `release-merge`, `shorebird-patch` and `test` the first time its workflows
are listed (and a new version of one when the engine ships another document). They compose the steps in the
order of `ship.sh`. **The job that builds has no step only the engine may run** (ADR 0010), so that it can be
leased to a runner: the guards, the gates, the uploads, the tag and the pushes are in engine jobs of an earlier
or later stage, and the uploads take what the runner built from the engine's artifact store (`artifactsFrom`).

| Workflow | Stages | Notes |
|---|---|---|
| `dev-build` | `check`, `build`, `upload` (each: platform x flavor) | No lock: as many as the slots allow. `check` (engine): `git.checkout`, `guard` source and credentials. `build` (runner-eligible): `git.checkout`, `version.bump` (a dev build pushes nothing, so the version commit stays in the job's worktree), `build.android` / `build.ios`, `record.manifest`. `upload` (engine, only for a platform and flavor that has something to upload): `upload.firebase` (an Android build with an app id in `firebaseAppIds`) or `upload.appStore` (an iOS build with an id in `appleAppIds`). |
| `prod-release` | `prepare`, `check`, `build`, `upload`, `finalize` | `lock: project`. `prepare` (engine) bumps the version once, cuts the release branch after `gate: prod_release` and pushes the branch after `gate: push`, so that a runner can fetch the version commit (ADR 0009). `check` (engine): `versionSync`, `buildNumberReuse`, `credentials`, and the store checks, from that commit. `build` (runner-eligible): `git.checkout` from that commit, `shorebird.release` (a Shorebird flavor) or `build.android` / `build.ios`, `symbols.archive`, `record.manifest`. `upload` (engine): `upload.play`, `upload.firebase`, `upload.appStore`, the ones the flavor has credentials for. `finalize` (engine) tags, pushes the tag and opens the release pull request (`github.createPr`). The approval of the push covers the tag push too (it binds to the same project, commit, version and run). A run of it is a release (see Releases). |
| `release-merge` | `merge` | Merges the pull request of a release: `gate: merge`, then `github.mergePr`. Started by `POST /releases/{id}/merge`, no project lock. |
| `shorebird-patch` | `check`, `patch` (platform x flavor), `finalize` | `lock: project`. Dispatch it with `releaseVersion` (`x.y.z+build`, never `latest`). `check` (engine): the guards, and `gate: prod_patch` in front of the last of them (so that the owner is asked only about a patch that passed the others). `patch` (runner-eligible): `git.checkout`, `shorebird.patch`. `finalize` (engine): the patch tag `v<x.y.z>+<build>-p<n>` and `gate: push`. |
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

## Runners

A runner is a machine that runs jobs for the engine (D-08, D-19): another Mac for `ios-sign`, a Linux box for
`android`, `flutter` and `swift-linux`. The engine is also a runner (the local one). Phase 14a is the engine
side: the protocol, the leases, the probe and the endpoints. The runner agent, `xp runner`, is Phase 14b
(see The runner agent below).

### Pairing

Setting up a runner step by step: [docs/guide/runners.md](docs/guide/runners.md). How a runner on
another machine reaches the engine (Tailscale, Cloudflare Tunnel, an SSH tunnel):
[Reaching the engine](docs/guide/runners.md#reaching-the-engine).

```sh
xp runners url https://mac.tailnet.ts.net   # the address runners reach the engine at; pairing commands carry it
xp runners pair mac-mini        # on any machine with a cli token: prints the pairing command, once
# on the runner machine: xp runner pair --engine <url> --token <pairing token> exchanges it for the credential
xp runners revoke mac-mini      # kills the credential, the connection and the leases
```

- **Pairing token** (`POST /runners/pairing-tokens`, `app` and `cli` tokens only: a paired runner receives signing
  material, so an `mcp` token must not be able to pair one). `xpp_` and 43 URL-safe characters, **single use**, valid
  for **15 minutes**, bound to the name of the runner. Only its SHA-256 is stored. The names of runners are unique,
  revoked runners keep theirs.
- **Exchange** (`POST /runners/pair`, no bearer token: the pairing token is the proof). It makes the runner and its
  credential, a device token of kind `runner` (D-06), which is shown once; only its hash is stored. Two exchanges of one
  token make one runner (a compare-and-set on `used_at`). Unknown, expired and used tokens answer `401`.
- **Revoke** (`POST /runners/{id}/revoke`, `app` and `cli`): the credential stops authenticating, the connection closes
  (code 4003) and every lease the runner holds ends **at once**, each job by the loss rule below. Revoking again
  changes nothing. `GET /runners` lists the runners with their status (`offline`, `online`, `draining`, `revoked`), the
  capabilities the probe found, the slots and the jobs they hold; `app`, `cli` and `mcp` tokens can read it.
- **A runner token is scoped to the runner endpoints** (ADR 0011): `GET /runners/connect`,
  `GET /runners/bundle` (the bundle a runner updates itself with, see Runner updates) and
  `PUT /runners/jobs/{id}/artifacts/{name}` and nothing else. Every other route answers a `runner` token
  `403 forbidden` with a message that names the route (`runnerScopeMiddleware`, in front of the router, so a
  route added later is closed to runner tokens until someone opens it). A runner holds signing material for
  the jobs it leases, so a stolen credential must not be able to read projects, jobs, credentials or approvals.

### The connection

A runner dials out (nothing connects to it): `GET /runners/connect`, a WebSocket with the credential as the bearer
token (other kinds of token answer `403`; browsers are refused). Every text frame is a JSON object with a `type`.
`RunnerFrame` (runner to engine) and `EngineFrame` (engine to runner) are sealed types in `packages/xp_api`
(`runner_protocol.dart`), and `openapi.yaml` describes each frame as a schema; contract tests check the frames the
real engine sends against them.

| Runner sends | Engine sends | What |
|---|---|---|
| | `welcome` | the runner's id, the heartbeat interval (30 s) and the lease length (90 s) |
| `hello` | `probe` | version, os, arch, cores, optional `maxJobs`, the leases it still holds; then the probe commands |
| `probe_result` | | the results; the engine derives the capabilities and the runner is online |
| | `lease_offer` | a job: its steps with their state, the capabilities, the repository (SSH URL and GitHub id) and the exact commit, the keys of the secrets it may ask for |
| `lease_accept`, `lease_reject` | | take or refuse the offer (`draining`, `busy`) |
| `heartbeat` | `heartbeat_ack` | renews the leases it lists; the ack says until when |
| `log_chunk` | `chunk_ack` | numbered output lines; `stored`, `duplicate` or `gap`, and the chunk wanted next |
| `step_state` | | where a step is; idempotent |
| `job_done` | `done_ack` | ends the job; the ack says the state the engine recorded |
| `secret_request` | `secret_value`, `secret_denied` | signing material of the leased job (D-09) |
| `drain` | | asks for no more jobs, or starts again |
| | `cancel` | stop this job: the lease is gone, the job was cancelled, or the engine does not know the lease |
| | `fault` | a frame the engine could not use |

A second connection of the same runner replaces the first (close code 4001). The engine closes with 4008 when a
runner sent nothing for a whole lease or did not answer the probe in 60 s, and with 4400 for something that is not a
frame (also: the first frame must be `hello`). A frame the engine cannot read is answered with a `fault` and
ignored; a runner ignores a type it does not know. The engine pings every 30 s.

### Capability probing (D-19)

The engine does not trust what a runner says about itself; the `hello` carries no capabilities. After every `hello` it
sends fixed commands (`RunnerProbe`) and derives the capabilities from what they print, with the same rules as
`LocalCapabilities` for the engine's own machine: `flutter` when `git --version` runs, `android` when a folder with
`platform-tools`, `cmdline-tools` or `build-tools` is `ANDROID_HOME`, `ANDROID_SDK_ROOT` or a default place of Android
Studio, `ios-sign` on macOS (`uname -s`) when `xcode-select -p` and `xcodebuild -version` find an Xcode, `swift-linux` on
Linux when `swift --version` runs, and `ios-linux` on a Linux runner started with `XP_IOS_LINUX_DIR`: the runner adds
the commands of that omarchy-apple-dev checkout and sends the folder (`iosLinuxDir`), and the engine checks its
commit against the pin of this release, Swift, the darwin SDK bundle, `rcodesign`, the llvm tools and
the pymobile3 python, each missing piece with its fix (`xp runner doctor` runs the same checks, and
`install-service` writes the variable into the service). A runner without the variable never lists `ios-linux` as
missing. Nothing touches a keychain, and `xcodebuild` and `swift` are not even started where
macOS would answer with a dialog (`requires` and `onlyOn` in the command). A runner gets jobs only after it answered; a
change of capabilities since the last connection is recorded as a `runner.capabilities_changed` event. The slots are
`maxJobs` of the `hello`, else a quarter of the cores, at least one; iOS jobs (`ios-sign` or `ios-linux`) run one at a time per runner.

### Leases and the 90 second rule (D-08)

The lease is the single source of truth for where a job runs. The scheduler places a queued job on a runner; the job
becomes `running` with `runner_id` and `lease_until` (now + 90 s) and the runner gets a `lease_offer` with the id of
the lease. A heartbeat every 30 s renews the leases it lists (idle runners send one too). Every later message about
the job carries the lease id, so a runner that comes back after its lease was lost cannot touch the job: it is
answered with `cancel`. The sweep (`LeaseSweeper`, every 10 s) ends the leases that ran out:

- A job whose steps have **no side effect left to do** is put back in the queue (its running step is `interrupted`,
  the job runs again from its first unfinished step, possibly on another runner).
- A job with a **step with side effects that is not done** (the running one, or one still to come) is
  `waiting_for_resume` and is **never re-queued**: the runner may only be unreachable and still doing it (D-08, D-18).
  `POST /jobs/{id}/resume` runs it again; steps with side effects ask their `alreadyDone` first.
- Heartbeats are idempotent; one that arrives after the lease ran out finds it lost. A connection that drops keeps
  its leases until they run out; a runner that comes back in time shows the leases it holds in its `hello` and they
  continue. The engine restarting does the same as a crash for the jobs on runners (ADR 0006): the recovery marks
  them, and the `hello` of a runner that still holds one is answered with `cancel`.
- A runner that refuses an offer gets none for 15 s (`draining` takes it out until it says otherwise), so a refusal
  cannot become a loop. Cancelling a job on a runner ends it at once and tells the runner.

### Logs, steps and artifacts

- **Log chunks.** A runner numbers its chunks from 1 per lease and keeps each until acknowledged. The engine stores the
  next one, answers a chunk it has with `duplicate` and one that skips ahead with `gap` (nothing is stored; the runner
  sends again from `next`). The lines get the job-wide `seq` of the job's log like local output does, are masked again
  with every secret the engine knows, and reach `GET /jobs/{id}/logs` followers. `job_done` carries the number of the
  last chunk; the engine ends the job only when it has the log up to there.
- **Steps and results.** `step_state` is accepted when it is newer (more attempts, or a later state of the same
  attempt) and ignored otherwise. A job reported `succeeded` while a step is not done is recorded `failed`.
- **Artifacts.** `PUT /runners/jobs/{id}/artifacts/{name}?kind=apk` with `X-Content-SHA256`, `X-Lease-Id` and
  `Content-Length`: the bytes are hashed as they stream into the artifact store, which commits the file only if the
  digest and the size are what was declared, so a wrong or half upload leaves nothing and never replaces a good file.
  The runner must hold the lease of the job. The answer is the `Artifact`. This is the existing store and recorder, so
  retention and downloads work as for local builds.

### What never goes to a runner

- **Steps only the engine runs.** A job is leased as a whole, so a job with one of these steps runs on the engine
  (`RemoteStepPolicy`): `upload.*` (D-09), `git.push`, `git.tag`, `git.releaseBranch` and `github.*` (they push and
  talk to GitHub with the token that stays on the engine, D-05, D-07), `gate` (approvals are the engine's, D-13),
  `guard` (its checks read credentials and ask the stores) and `test` (it judges against the baseline and stores
  the run, both in the engine's database, D-21). `shorebird.release` and `shorebird.patch` may run on a runner
  (ADR 0012). The scheduler never places a job with an engine-only step on a remote runner and the hub refuses
  it again at the offer. The built-in workflows keep these steps in jobs of their own, so their build jobs can
  go to a runner (ADR 0010).
- **Secrets (D-09, ADR 0012).** Over the authenticated socket, on request, never in the offer: the offer lists
  **keys only**, the runner asks with `secret_request` and gets `secret_value` (the base64 of the bytes)
  **once per lease and key**. What may be asked for is what the steps of this job name in `secretFiles`,
  `secretEnvironment` or `tokenSecret` **and** that is the keystore of the project or one of its passwords, or the
  Shorebird key of the project (`RunnerSecretGrants`); the GitHub token, store credentials and anything else are
  `secret_denied`. Each delivery is a `runner.secret_delivered` event (key, never value), and the delivered
  text is added to the log masker. A single-use URL was the other option; the socket is already authenticated,
  bound to the lease and outbound only, and needs no second credential to leak. The socket is not encrypted by
  `xpd` itself (see `--host` above): a runner on another machine should reach the engine through TLS (a reverse
  proxy or a tunnel), because the socket carries signing material. The runner wipes the secret at the end of the
  job and at its start (see The runner agent).
- **The source (ADR 0009).** The offer names the repository (its SSH URL and GitHub id) and the exact commit and
  never a credential; the runner fetches the commit with its own SSH key.

### The runner agent

`xp runner` is the other end of everything above (`apps/xp/lib/src/runner`). What a runner does
while the engine is away for hours, and what happens to its jobs:
[docs/guide/runners.md](docs/guide/runners.md#when-the-engine-is-away).

```sh
xp runner pair --engine https://xpath.example.com --token xpp_...   # once; xp runners pair <name> made the token
xp runner start [--slots 4] [--one-shot] [--data-dir ~/runner]      # connects out and runs jobs until stopped
xp runner install-service [--slots 4]                                # keeps it running, and lets it update itself
```

- **Pairing.** `pair` checks the engine (`GET /version`), exchanges the pairing token (`POST /runners/pair`) and
  keeps the credential in the secret store of the machine: the Keychain on macOS (service
  `ly.abdurahman.xpath.runner`), an encrypted file in the data directory on Linux (`XP_TEST_FILE_SECRETS=1` forces
  the file, for tests). It is never printed or logged. `runner.json` in the data directory holds who the runner is
  (engine, id, name) and no secret. `--name` only warns when the engine named the runner otherwise: the pairing
  token fixes the name. Pairing again in a paired data directory needs `--force`.
- **Data directory** (`--data-dir`, else `$XP_RUNNER_DATA_DIR`, else `~/.local/share/xpath/runner`):
  `source/mirrors/<repo id>.git` (the bare cache), `source/worktrees/<repo id>/<job id>` (fresh worktrees),
  `jobs/<job id>` (what a job leaves before it is uploaded), `toolchains/flutter`, `secrets/` (where no tmpfs is
  available), `keychains/`, `state/pgids.json`, and for updates and services `versions/<version>/` (the installed
  `xp` bundles), `current` (a symlink to the version that starts), `update.json`, `service-logs/` (see Runner updates
  and Running as a service).
- **Connection.** Outbound only, with the credential. It reconnects with an exponential backoff (1 s doubling to
  60 s, half of each delay random so that runners that lost the same engine do not come back together) and starts
  the backoff again after a connection that worked. It stops for good when the engine revokes it (close code
  4003), when another connection of the same runner replaced it (4001) or when the credential is refused.
- **Hello and probe.** After the welcome the runner says hello (version, system, architecture, cores, `--slots`
  as `maxJobs`, whether it drains, the leases it still holds) and runs the commands of the probe the engine sends
  (`ProbeExecutor`: `onlyOn`, `requires`, not installed, timeouts, 64 KiB of output). It claims no capability; the
  engine derives them from the results (D-19).
- **Leases.** It accepts an offer within its slots (`--slots`, else a quarter of the cores) and refuses the rest
  with a reason: `busy` (the slots are taken, the job runs here already, or another `ios-sign` job runs: those
  run one at a time), `draining`, `unsupported` (a step this runner has no implementation for). It heartbeats
  every `heartbeatSeconds` of the welcome (30 s), listing its leases, also those whose end the engine has not
  acknowledged yet.
- **The job** runs through the engine's step runner (`JobRunner` and `StepRegistry` of `xp_engine`, the process
  supervisor of `xp_adapters`: every process in its own group, ADR 0003) with the steps the engine lets a runner run
  (`RunnerSteps`). The paths of the engine's disk in the steps (`worktree.path`, `mirror.path`, a working
  directory below it) are translated to the runner's (`LeasePaths`). Every step of the offer starts again, since
  the work of an earlier lease is not on this machine, but the attempts are kept, so that a step with side effects
  asks first whether its work exists (`alreadyDone`). `step_state` frames report each new state of a step.
- **Source (ADR 0009).** `git.checkout` is `RemoteCheckoutStep`: it fetches the exact commit of the offer into the
  runner's own bare cache (`git fetch origin <sha>` with `GIT_SSH_COMMAND='ssh -o BatchMode=yes'`, no global git
  configuration, no prompt), cuts a fresh worktree and verifies `HEAD == sha` before anything runs. A key that
  cannot read the repository fails the job with "add this runner's SSH key as a deploy key on `<owner/repo>`", an
  unknown host key with "run `ssh -T git@github.com` once", a commit that was never pushed with "push it". The
  machine needs `git`, `ssh` and its own access to GitHub (a deploy key or the key of a user). **Test only:**
  `XP_RUNNER_TEST_SOURCE_URL` replaces the URL of every lease (the end-to-end test points it at a local bare
  repository); a real runner never sets it.
- **Logs and reports.** The output of the processes goes to the engine as `log_chunk` frames numbered from 1 per
  lease (up to 500 lines or a quarter of a second each). The runner keeps every chunk, the newest state of every
  step and the end of the job until the engine acknowledges them, and sends them again after a reconnect or after
  a `gap` answer. `job_done` carries the last chunk and the explanation of a failure, and is resent until the
  `done_ack`. Artifacts a build records are uploaded to the engine with their SHA-256 and the lease before the step
  that made them ends (`PUT /runners/jobs/{id}/artifacts/{name}`, tried again on connection errors).
- **Per-job secrets (D-09, ADR 0012).** A step reads a secret like on the engine, from a secret store; here the
  store (`LeaseSecretStore`) asks the engine with `secret_request` the first time a step needs the key (only keys
  of the offer can be asked for) and keeps the answer in the job's secret folder. The folder is 0700, its
  files 0600: on Linux in a tmpfs (`/dev/shm`, else `$XDG_RUNTIME_DIR`), so the secrets never reach the disk; on
  macOS and elsewhere in `secrets/` of the data directory. The secret files of steps (`secretFiles`, bytes as
  they are, so a keystore stays binary) go to the same folder. **The folder is deleted when the job ends, however
  it ends (success, failure, cancel), and again at every start of the runner.** Delivered text is added to the
  runner's masker, so it is hidden in the log before it leaves the machine. For signing material that has to be in
  a keychain on macOS, `TemporaryKeychain` makes a keychain for the job (never the login keychain; created
  unlocked with a random password and set never to lock, over `security -i` so that the password is in no
  argument; added to the search list only if the build needs it, and the list put back when it is deleted);
  nothing the engine delivers today needs it, and a start of the runner deletes any that a crash left.
- **Cancel.** A `cancel` frame (the lease was lost, the job was cancelled, the engine does not know the lease)
  stops the job's process groups (`SIGTERM`, ten seconds, `SIGKILL`, ADR 0003), wipes its secrets and reports
  nothing more.
- **Start-up clean-up.** Before it connects, a start of the runner stops the process groups of steps that a runner
  killed with `SIGKILL` left (the groups are recorded in `state/pgids.json` while a step runs), deletes every
  secret folder and temporary keychain, and removes the work folders and worktrees of jobs. It prints what it
  found. This is what makes "no secret is left after a crash" true.
- **Drain and one-shot.** The first `SIGINT` or `SIGTERM` drains: a `drain` frame, no more offers, the running
  jobs finish and the runner exits 0. The second stops now: the jobs are cancelled, nothing is reported and the
  engine ends the leases when they run out. `--one-shot` takes one job, tells the engine to offer no more and
  exits after the engine acknowledged its end. Exit codes: 0 drained or done, 77 revoked or credential refused,
  73 replaced, 78 not paired, 69 `perl` missing, 75 switched to another version (see Runner updates).
- **Tests.** The agent, the outbox, the step and the secret folder are unit tests with fakes
  (`apps/xp/test/src/runner`); the wiring runs the real step runner against a fake engine on a loopback port
  (tag `process`); `TemporaryKeychain` has a `macos` test on a keychain of its own. `tool/e2e/runner_loss_e2e.sh`
  is the end-to-end proof: it pairs and starts a real runner, gives it two jobs that hold a keystore secret, kills
  it with `SIGKILL`, waits for the production lease (90 s plus the sweep) and checks the loss rule (a job with a
  declared side effect is `waiting_for_resume`, never repeated by itself; one without is queued again, both with
  a `runner.lease_lost` event), then restarts the runner and checks that no secret file, temporary keychain or
  process is left, and that a resumed job that is cancelled wipes its secrets and ends its process group.

### Runner updates (D-24)

A runner runs the version of `xp` its engine runs. The engine says its version in every `welcome`
(`engineVersion`); a runner whose own version is not that one updates itself **between jobs**, never in the middle of
one (`apps/xp/lib/src/runner/update`).

1. **Wait.** At the welcome the runner sees the difference. It says `draining` in its hello (the engine offers it
   nothing), refuses every offer it still gets with `updating`, and lets the jobs it holds finish, however long they
   take. When none is left (the engine acknowledged their end) the agent ends with `AgentExit.updateRequired`. A
   job is never cancelled to update. If the engine goes back to the runner's version meanwhile, the runner goes on
   as it was. A `--one-shot` runner does not update.
2. **Download.** `GET /runners/bundle?os=<os>&arch=<arch>` (the runner token reaches it, ADR 0011) streams the
   `xp` bundle of the engine's own version for the machine as a `.tar.gz`, with `Content-Length` and
   `X-Content-SHA256`. The runner checks the size and the digest before it unpacks anything, and refuses a
   response that does not announce them. The digest guards against a broken download; the engine is trusted for the
   content, as it is for the commands it has the runner run.
3. **Unpack and try.** `tar -xzf` into `updates/`, a check that `bin/xp` exists and is executable, and then
   `bin/xp --version`, which has to print the version the engine runs. A bundle that cannot start (the wrong
   architecture, a missing library) is found out here, while the old version still runs.
4. **Switch.** The bundle becomes `versions/<version>/` and the symlink `current` is moved to it in one step (a
   link made beside it and renamed over it). The version before stays, and when the runner did not run from
   `versions/` yet (the bundle it started from is copied there first), so does the one that ran. The runner then
   starts again as the new version: under a service manager (`XP_RUNNER_MANAGED=1`, which `install-service` sets) it
   exits with **75**, a failure, so that `KeepAlive` and `Restart=on-failure` start `current/bin/xp` again; started
   by hand it starts `current/bin/xp runner start --data-dir ...` itself on the same terminal, waits for it and
   exits with its code (Dart cannot replace a process; the old one holds nothing).
5. **Prove or roll back.** `update.json` records the update: the version before, the version after and how many
   times the new one started without the engine welcoming it. The welcome of the new version clears the record and
   deletes every version but the new one and the one before. A new version that started `3` times and never got a
   welcome (it crashes, or the engine refuses it) is replaced at its next start: `current` goes back to the version
   before, the failed version is remembered in `update.json` so that the runner does not update to it again, and
   the runner restarts. A newer engine version is another version and is tried.

An update that fails (no bundle on the engine, a wrong digest or size, a bundle that does not unpack or start, no
`tar`) changes nothing: the runner logs why (`Cannot update to version X: ...`), goes back to taking jobs as the
version it is and does not try that version again until it restarts.

**Where the bundles come from.** The engine serves the files it finds as `<os>-<arch>/xp.tar.gz`, in the first of
`<data-dir>/bundles/<engine version>/` and `runners/` next to its own `bin` and `lib` (the bundle of `xpd`). The
file is the `xp` bundle that `dart build cli -t bin/xp.dart` makes (`bin/xp`, `lib/libsqlite3.*`, ADR 0001) as a
`.tar.gz` whose top level is `bin` and `lib`. `os` and `arch` are what the runner reports in its hello (`macos` or
`linux`; `arm64`, `x86_64`). `tool/release/bundles.sh` puts the runner bundles of every target it built in the
`runners/` of each engine bundle (see Releases and installation); a bundle it did not build (the macOS ones in an
archive from CI) can go in `<data-dir>/bundles/<engine version>/`. The engine finds no file: `404`, "This engine has no runner bundle for linux-arm64. Put the xp.tar.gz of
this version in ...". The SHA-256 is worked out once per file and kept until the file changes.

**Tests.** `runner_update_test.dart` runs the real runner (`buildRunner`, the real `tar`, a real bundle folder whose
`bin/xp` prints its version) against a fake engine: an outdated runner finishes its job, updates, restarts and
reconnects with the new version in its hello; a wrong digest switches nothing; an engine without a bundle leaves the
runner as it was; a new version that fails to start is rolled back. The restart in the tests is an injectable
`Restarter`.

### Events

`runner.paired`, `runner.connected`, `runner.disconnected`, `runner.revoked`, `runner.capabilities_changed`,
`runner.lease_lost` (with the state the job is in now) and `runner.secret_delivered`; the job events (`job.state_changed`,
`job.step_changed`) are the same as for local jobs.

## Releases

A **release** is one flavor of an app going to the stores (D-17). The engine creates it when a workflow that cuts
a release branch (`git.releaseBranch`, so `prod-release`) is dispatched, one per flavor of the run, and follows it
to the end. `packages/xp_engine/lib/src/releases` has the logic, `apps/xpd/lib/src/api/releases` the endpoints.

```text
draft -> building -> uploaded -> in_review -> approved -> live -> merged
                                    |
                                    +-> rejected -> building (a new build of the same version)
                       any state that is not over -> abandoned
```

- **How it moves.** `ReleaseStateMachine` lists the allowed moves (a store that is quick, or an internal Play
  track, may take `uploaded` straight to `approved` or `live`). The service reads the steps of the jobs of the
  release (`ReleaseService.sync`): `building` once a build step started, `uploaded` once every store the release
  targets (`upload.appStore` is Apple, `upload.play` is Play) has its upload, and the branch, tag and pull request
  as their steps succeed. After that the **stores** decide, each with its own status (`pending`, `uploaded`,
  `in_review`, `rejected`, `approved`, `live`; kept in `store_status`): the release is `rejected` if any store is,
  else as far along as the slowest store (`in_review` while either reviews, `live` only when every store targeted
  is). A status only moves forward, and a rejection only before the approval. Reading a release brings it up to
  date with its jobs, and `ReleaseWatcher` does the same when a job or step event arrives.
- **Asking the stores** (D-14, D-15). Apple: App Store Connect `appVersionState` of the version with the API key
  (`IN_REVIEW`/`WAITING_FOR_REVIEW` are in review, `REJECTED`/`METADATA_REJECTED`/`INVALID_BINARY`/
  `DEVELOPER_REJECTED` rejected, `PENDING_*`/`ACCEPTED` approved, `READY_FOR_DISTRIBUTION` live); an Apple ID
  flavor has no key, so the iTunes lookup says the version is live when it is on sale in the app's storefront and
  approval is the owner's button. Play: `tracks.releases.list`, the release that holds the version code
  (`IN_REVIEW`, `NOT_APPROVED`, `APPROVED_NOT_PUBLISHED`, `PUBLISHED`); without a service account the owner presses
  "Play: live". `ReleaseStatusPoller` asks a store at most every ten minutes (the `checked_at` of its status is the
  cache, so a restart keeps it), also a store that fails, and a store that cannot be read keeps its status and says
  why in `note`. `ReleaseWatcher` checks what is due every minute; `POST /releases/{id}/refresh` asks at once.
- **By hand.** `POST /releases/{id}/stores/{apple|play}/status` takes `approved` or `live` for Apple and `live`
  for Play, once the store has the build. Because a status moves the release toward the merge of its pull request,
  it and `abandon` are for `app` and `cli` tokens (`403` for `mcp` and `runner`, D-13). A `runner` token reaches no
  release route at all (ADR 0011).
- **New build, same version.** After a rejection `POST /releases/{id}/builds` dispatches the workflow that made
  the release again, on its release branch, with the same version and a new build number (D-11, never reused) and
  the inputs of the first dispatch (`DispatchRequest.release` links the run; a workflow reads it as `release`, and
  `prod-release` skips the check that the version shipped before when it is set). The release goes back to
  `building`, the stores to `pending`; App Store Connect keeps reporting `REJECTED` for the version until the new
  build is submitted, so that reading is ignored until it changes. The new build is tagged and pushed (the branch
  moves forward only) and reuses the open pull request.
- **The pull request is opened after the push**, by the `github.createPr` step of `prod-release` (the release
  branch is not on GitHub before the gated push, so opening it when the release starts is not possible). An open
  pull request for the same branches is reused.
- **The merge** is enabled once every store targeted is live (`mergeEnabled`). `POST /releases/{id}/merge` runs the
  built-in `release-merge` workflow on the release branch; its `gate: merge` binds the approval to the project,
  the commit and `x.y.z+build`, so it waits for an `app` or `cli` token to approve it (an `mcp` token gets the pending
  approval and can poll, never approve). `github.mergePr` then merges with a **merge commit** (ADR 0007: it calls
  `mergePullRequest` without a method, and the e2e asserts `merge_method: merge`), only when the release is `live`
  and only the commit that was tagged (`sha` is sent, so a push to the branch since is refused with GitHub's
  `409`). The release is `merged` when the step succeeded. A merge run that ends without merging (a denied gate, a
  GitHub error) frees the merge to be asked for again, and asking while a run is under way answers with it.

| Route | What it does |
|---|---|
| `GET /releases[?project=&app=&state=]` | The releases, newest first, each brought up to date. |
| `GET /releases/{id}` | One release: state, `version`, `build`, `builds`, the status in each `stores`, `branch`, `tag`, `headSha`, `prNumber`, `prUrl`, `mergeEnabled`, `mergeCommit`. |
| `POST /releases/{id}/refresh` | Asks the stores now (bypasses the ten-minute cache). Any token but a `runner` one (ADR 0011). |
| `POST /releases/{id}/stores/{store}/status` | `{"state": "approved" or "live"}`. `app` and `cli` tokens; `409` when the store has no build yet or is past that status. |
| `POST /releases/{id}/builds` | New build, same version. `202` with the run; `409` unless the release is `rejected`. |
| `POST /releases/{id}/merge` | Request the merge. `202` with the run, which waits for approval; `409` unless the release is `live` with a pull request. |
| `POST /releases/{id}/abandon` | `{"reason"}` optional. `app` and `cli` tokens; cancels a run that still builds it. |

`release.created`, `release.state_changed` and `release.store_changed` go on `/events`.

## Notifications and housekeeping

`packages/xp_engine/lib/src/notify` tells the owner what matters (D-22); `.../housekeeping` keeps the disk in
check (D-22, D-24). The endpoints are in `apps/xpd/lib/src/api/storage`.

### Notifications

`Notifier` listens to the event log. `NoticeFactory` decides which events are worth telling: a **production job**
(a job of a release, or of a run that holds the project lock) that failed or succeeded, an approval that was
requested, decided or expired, a release that was rejected, approved, went live or was merged, a credential that
expired, and secrets that are locked (D-10, from `SecretStore.statusChanges`). Each becomes

- a `notification.raised` event (`kind`, `level`, `title`, `body`, and the project, release, job or approval it
  is about), which the macOS app shows as a notification (Phase 16b; the engine only raises the event); and
- a Slack message to the webhook of a `slack` credential assigned to a flavor of the project, if it has one (the webhook URL comes from
  the secret store, `HttpSlackWebhook` posts it with `package:http`). The text goes through the secret masker and
  is cut to 600 characters. A message is tried again after 1, 5 and 30 seconds (or as long as Slack's
  `Retry-After` says, at most a minute); one that still fails is reported on stderr and dropped. Messages of one
  project go out in the order of the events. Locked secrets go to the app only: the webhook is one of the secrets
  that cannot be read then.

The same notice (same `kind` and subject) within 15 minutes is told once, so a flapping state does not repeat,
and at most 20 messages a minute go to Slack. The app is told even when Slack is not.

**`min_version_*` reminder.** Raising `min_version_android` and `min_version_ios` in Firebase Remote Config is only
right once the new version is approved *and available* in that store (`mataa_new_app/docs/RELEASING.md`). When a
store reports a release `live`, a `min_version_reminder` notification names the variable of that store
(`min_version_ios` for the App Store, `min_version_android` for Google Play) and the version. XPath does not know
whether a release is a forced update, so the text says "if this is a forced update"; it is a reminder only and
calls no remote-config API.

**Release notes.** `GET /releases/{id}/notes` lists the commits (merge commits and XPath's own
`chore(release)` version commits left out) between the previous release tag and the commit of the release, from the
engine's mirror (it does not fetch). The previous tag is the newest non-patch tag of the same app and flavor, by the
project's release model, with a lower version; a first release lists its latest 100 commits. Commits are grouped by
conventional-commit type (breaking changes, features, fixes, performance, refactoring, documentation, other), and
the response has the groups plus the text twice: Slack `mrkdwn` (`*bold*`, `<url|Full changelog>`, `&`, `<` and `>`
escaped) and WhatsApp text (`*bold*`, the link as plain text). `409` while the release has no commit yet.

### Housekeeping

`HousekeepingPlanner` decides, `HousekeepingService` reports and does it.

| Category | What goes | What stays |
|---|---|---|
| `artifacts` | The files of builds past the newest `keepPerFlavor` (5 unless set) of each flavor of each app. A build is a run, so one release that builds iOS and Android and records a manifest is one build. | Pinned artifacts; every artifact of a release that is **not over** (`draft`, `building`, `uploaded`, `in_review`, `rejected`, `approved`, `live`), also those of the runs that built or merge it; artifacts of jobs that have not finished. |
| `logs` | The log folder and the record of jobs that finished more than `logDays` (90, D-24) ago. | The record of a job that a release not over needs, whose test run is a **current baseline** (the job row cascades to its test run, D-21), or that still has an artifact. |
| `worktrees` | Worktrees of jobs that succeeded or were cancelled, of failed jobs after 7 days, and of no job at all. | Worktrees of jobs that have not finished, of failed jobs for a week (they can be resumed) and of failed jobs of a release not over. |
| `mirrors` | Mirrors of repositories that are no longer projects (removing a project leaves its mirror, D-05). | Mirrors of projects. |
| `flutter` | SDKs of the cache that no app pins in `.fvmrc`, no Shorebird release was built with (D-20) and no unfinished job uses. | The others. |

- **Daily.** `HousekeepingSchedule` prunes the logs (and the records that nothing needs) at the start when the last
  pruning was a day ago or never, then every 24 hours, on the `Clock`. Nothing else is deleted by itself: the
  owner presses "free up space".
- **Retention settings** are kept in the `housekeeping_setting` table (migration 12): `GET`/`PUT
  /storage/retention` (`keepPerFlavor` and `logDays`, both at least 1).
- **Who may delete.** Deleting is a gated action (D-13), but a gate binds an approval to one project, a commit and
  a version, and housekeeping spans every project. So it is treated like `abandon` and the store statuses: only
  `app` and `cli` tokens may delete (`"dryRun": false`) or change the retention, and that token is the owner
  approving; `mcp` tokens get `403` and may only read the report and dry-run, and `runner` tokens reach nothing here (ADR 0011).

| Route | What it does |
|---|---|
| `GET /storage` | The report: per category the bytes held and the bytes that would be freed, and the artifacts by app and flavor. Deletes nothing. |
| `POST /storage/free` | `{"dryRun": true, "categories": [...]}`, both optional. A dry run (the default) says what would be freed; `"dryRun": false` deletes (`app`/`cli` tokens), artifacts first, and answers what was freed and what could not be. |
| `GET /storage/retention`, `PUT /storage/retention` | `{"keepPerFlavor", "logDays"}`. `PUT` is for `app` and `cli` tokens. |

## The `xp` command line

`xp` mirrors the API (Phase 13). It is built on `CommandRunner`, `mason_logger` and `cli_completion`
(`xp completion`, `xp install-completion-files`), and talks to the engine only through `xp_client`.

```sh
xpd token create --name "My Mac" --kind cli                     # on the engine machine; printed once
xpd token create --name "Claude" --kind mcp                     # a second token, for `xp mcp`
xp connect http://127.0.0.1:7480 --token <cli token> --mcp-token <mcp token>
xp projects add acme/app            # or a folder on the engine machine
xp workflows list acme/app
xp dispatch acme/app dev-build --flavor dev --platform android
xp logs -f <job id>
```

**Connecting.** `xp connect <url> --token <token> [--mcp-token <token>]` checks that the URL is an engine of this API
version (`GET /health`, `GET /version`, no token needed) and that each token works (an authenticated
`GET /projects`), and only then saves anything. The engine URL goes to `xp.json` in `$XP_CONFIG_DIR`, else
`$XDG_CONFIG_HOME/xpath`, else `~/.config/xpath`. **The tokens never go in that file**: they go to the OS secret
store (`packages/xp_secrets`, the same code as the engine's), under the names `token.cli` and `token.mcp`. On macOS
that is the login Keychain, service `ly.abdurahman.xpath.client` (ADR 0005); on Linux it is `secrets.enc` in the config
folder, sealed with `$CREDENTIALS_DIRECTORY/xpath-master-key` or a 0600 `master.key` beside it. `XP_ENGINE_URL`,
`XP_TOKEN` and `XP_MCP_TOKEN` override what was saved, so scripts need to save nothing and never touch a Keychain;
`XP_TEST_FILE_SECRETS=1` keeps the tokens in the file store even on macOS (the end-to-end scripts use it).
`xp mcp` uses the `mcp` token and the CLI the `cli` token: they are two tokens, one per client (D-06, D-12).

**Commands.** A project is named by its id (`prj_...`), `owner/name` or just `name`; a workflow by its id
(`wf_...`) or its name. Every command takes `--json` (before the command: `xp --json projects list`) to print what
the API answered, for scripts; otherwise it prints text and tables.

| Command | API |
|---|---|
| `xp connect <url> --token T [--mcp-token T]` | `/health`, `/version`, `GET /projects` |
| `xp projects list`, `show <p>`, `add <folder or owner/name>`, `scan <p>`, `remove <p>` | `/projects` |
| `xp credentials list`, `show <c>`, `add --kind <kind> --name <name> [options of the kind]`, `rename <c> <new name>`, `replace <c> [options of its kind]`, `verify <c>`, `remove <c> [--force]` | `/credentials`; a credential is its id (`crd_...`) or its name in any case; see Credentials below |
| `xp credentials assign <c> --project <p> (--flavor <f> \| --all-flavors) [--app <path>] [--replace]`, `unassign <c> --project <p> --flavor <f> [--app <path>]` | `PUT` and `DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}`, the kind being the credential's |
| `xp workflows list <p>`, `show <p> <w> [--version n]`, `validate <p> -f file`, `create <p> <name> -f file`, `edit <p> <w> -f file` | `/projects/{id}/workflows` (`validate` exits 65 and prints `line:column: message`) |
| `xp dispatch <p> <w> [--ref --app --flavor --platform --bump --version --release-version --input k=v]` | `POST .../dispatch` |
| `xp runs show <run>`, `cancel <run>` | `/runs/{id}`; `show` names the approval a waiting run needs |
| `xp jobs show <job>`, `cancel <job>`, `resume <job> [--from-step n]` | `/jobs/{id}` |
| `xp logs <job> [-f] [--after seq]` | `/jobs/{id}/logs` (WebSocket) |
| `xp approvals list [--project --state]`, `show <a>`, `approve <a> [--reason]`, `deny <a> [--reason]` | `/approvals`; the CLI token is a `cli` token, which may decide (D-13) |
| `xp gates show <p>`, `tighten <p> <action>...` | `/projects/{id}/gates`; only the app loosens a gate |
| `xp releases list`, `show <r>`, `refresh <r>`, `status <r> <apple\|play> <state>`, `build <r>`, `merge <r>`, `abandon <r>`, `notes <r> [--format slack\|whatsapp]` | `/releases` |
| `xp storage report`, `free [--apply] [--category c]`, `retention [--keep n] [--log-days n]` | `/storage` (`free` is a dry run unless you pass `--apply`) |
| `xp runners pair <name>`, `revoke <runner>` | `POST /runners/pairing-tokens`, `POST /runners/{id}/revoke` (a runner is its name or id); see Runners |
| `xp runner pair`, `start` | the runner agent of this machine (`POST /runners/pair`, `GET /runners/connect`); see The runner agent |
| `xp runner install-service`, `uninstall-service`, `service-status` | the LaunchAgent or systemd unit of the runner of this machine, no engine call; see Running as a service |
| `xp artifacts list <job>`, `download <a> [-o path]` | `/jobs/{id}/artifacts`, `/artifacts/{id}/download` (checks the SHA-256 the engine sends) |
| `xp mcp` | see below |

`xp logs` without `-f` prints the log so far and stops once the engine has been quiet for 750 ms; with `-f` it follows
the job until it ends, reconnecting with the last line it printed if the connection drops, and exits 1 if the job
failed, was cancelled or was interrupted.

**Credentials.** `xp credentials` (also `xp credential`) manages the named credentials any flavor may use, one per
kind. `add` and `replace` take the options of the kind: `asc_key` `--key-id`, `--issuer-id`, `--p8 <file>` and
`--key-kind team|individual`; `apple_id` `--apple-id`; `play_sa` and `firebase_sa` `--service-account <JSON key
file>`; `keystore` `--keystore <file>` and `--key-alias`; `shorebird` and `slack` none. A secret is never an
argument: at a terminal `xp` asks for it without showing what you type, otherwise it reads it from standard input
with its flag (`--password-stdin`, `--store-password-stdin`, `--key-password-stdin`, `--token-stdin`,
`--webhook-url-stdin`), one per command since standard input is read once. A keystore's key password is optional
(empty: the store password). Without a terminal and without the flag the command stops with a usage error that
names the flag. `--kind github` is refused: the engine has one GitHub token, set in the app's Settings or with
`xpd secrets import-gh`.

```sh
xp credentials add --kind asc_key --name "Acme ASC" --key-id ABC123 --issuer-id <issuer> --p8 AuthKey_ABC123.p8
printf %s "$SHOREBIRD_TOKEN" | xp credentials add --kind shorebird --name Shorebird --token-stdin
xp credentials assign "Acme ASC" --project acme/app --all-flavors
xp credentials remove "Acme ASC" --force
```

`remove` refuses a credential that flavors use, lists them and exits 73; `--force` removes it from every flavor
first. `assign --all-flavors` leaves a flavor that has another credential of the kind as it is unless `--replace`,
and lists the flavors that kept theirs. `verify` checks the credential and every flavor that uses it, and exits 1
when a check refuses it.

**Exit codes.**

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | the command ran, and the job it followed, the free-up, the download or the credential check failed |
| 64 | usage error (also a `400` from the engine) |
| 65 | the engine refused the content: an invalid workflow, a rejected credential (`422`) |
| 66 | no such project, job, run, approval, release, artifact or credential (`404`), or a file `xp` cannot read |
| 69 | the engine cannot be reached, or cannot serve (`502`, `503`: secrets locked) |
| 70 | the engine failed (`500`) |
| 73 | a conflict (`409`): an approval decided already, a project added already |
| 75 | `xp runner start` switched to another version (an update or a rollback); its service manager starts it again, or `xp` started the new version itself and this is its code |
| 77 | the token is rejected (`401`), or its kind may not do this (`403`) |
| 78 | not connected: `xp connect` first |

**The update check.** Once a day `xp` asks GitHub for the latest release of `AbdurahmanAlmehdi/x-path` and prints a
line on standard error if it is newer than the running version. It is a plain unauthenticated `GET` of the public
release list with a fixed `User-Agent`: it sends no version, machine, user or engine address (D-24: no telemetry),
caches the answer for a day in `update-check.json` beside `xp.json`, fails silently, runs beside the command, is never waited for more than a moment, and does not run
for `--json` or `xp mcp`. `XP_NO_UPDATE_CHECK=1` turns it off.

## `xp mcp`

`xp mcp` is an MCP server on standard input and output (Phase 13, D-12) for agents such as Claude Code:

```sh
claude mcp add xpath -- xp mcp
```

It is a thin adapter: `apps/xp/lib/src/mcp/dart_mcp_adapter.dart` is the **only** file that imports `dart_mcp`
(pinned to exactly 0.5.2, which supports stdio only: enough for 1.0; the plan moves to Streamable HTTP when 0.6 is
published). Everything else works with `McpTool`, so an API change of `dart_mcp` stays in that file. Standard output
carries MCP messages only; whatever else it has to say goes to standard error. It uses the **`mcp` token** saved with
`xp connect --mcp-token`, never the CLI's.

The tools (all of them answer with JSON text, or with `isError` and a message):

| Kind | Tools |
|---|---|
| Read | `list_projects`, `get_project`, `list_workflows`, `get_workflow`, `get_run`, `get_job`, `get_job_log_tail`, `list_artifacts`, `get_job_tests`, `get_test_baselines`, `list_releases`, `get_release`, `get_release_notes`, `list_approvals`, `get_approval`, `get_gates`, `get_storage_report`, `list_runners`, `list_credentials` (names, kinds, accounts, checks and the flavors that use each; never a secret; no tool adds, assigns or removes one) |
| Create and edit | `add_project`, `scan_project`, `update_project`, `validate_workflow`, `create_workflow`, `update_workflow` (a document is validated first; with issues nothing is saved and they come back with `line` and `column`) |
| Run | `dispatch_workflow` |

**Gates (D-13).** There is no tool to approve, deny, merge, abandon, delete or change a gate, and the engine answers
`403` to an `mcp` token that tries it by hand anyway. A gated action, such as a production release, stops at its gate:
`get_run` then shows the run as `waiting_for_approval` with `pendingApprovals`, the agent tells the owner, who approves
in the app or with `xp approvals approve <id>`, and the agent polls `get_approval` until the state is no longer
`pending`. An approval nobody decides within 24 hours expires, which counts as denied.
`tool/e2e/mcp_gate_e2e.sh` proves it against a real engine: it speaks MCP JSON-RPC to a real `xp mcp` subprocess,
dispatches `prod-release`, sees the run stop at a pending approval, gets `403` for the MCP token on approve, deny and
loosening the gate, and approves with an app token.

## The client library

`packages/xp_client` is the Dart client of the API that `xp`, `xp mcp` and the desktop app share. It depends on
`xp_api` only, has a method per endpoint (the ones in `openapi.yaml`: projects, scans, credentials, workflows,
dispatch, runs, jobs, artifacts, test runs, approvals, gates, releases, storage, runners) and 100% test coverage.
The runner methods are what the runner agent uses: `pairRunner` (no token), `connectRunner` (the WebSocket; the
caller speaks the frames of `xp_api`) and `uploadRunnerArtifact` (streams the file with its SHA-256 and size).

- **Errors.** Every error is an `XpClientException`. A non-2xx answer is an `ApiException` with the status, the
  `ApiErrorCode` of the error envelope (`null` if the answer was not one) and, for `already_decided`, the approval as
  it stands. A network failure, a timeout or an answer that is not JSON is a `ConnectionException`.
- **Events.** `watchEvents({after})` is `GET /events` with a resume cursor: it remembers the `seq` of the last event it
  passed on, and when the connection drops reconnects with `?after=<seq>` after a growing delay (1 s doubling to 30 s,
  reset by a connection that delivered something), so the listener sees each event once, in order. A `StreamOpened`
  frame starts every connection but only a stream without a cursor takes its `seq` (the head of the log). When the
  engine cannot resume (`409 resync_required` on the upgrade, or the close code 4409) the stream emits
  `EventsResyncRequired`, reconnects without a cursor and carries on: the listener reloads its state over HTTP. A
  refused token ends the stream with the `ApiException`.
- **Logs.** `followJobLogs(job, {after})` is `GET /jobs/{id}/logs` the same way: lines in order, each once, the end
  frame last. A `gap` frame (the client read too slowly) makes it reconnect from the line before the gap, so the
  lines it missed arrive after all.
- **WebSockets.** The default connector does the upgrade by hand over `dart:io`, because `WebSocket.connect` throws away
  the body of a refusal, and that body is the error envelope. Tests pass their own connector and clock.
- **Downloads.** `downloadArtifact(id)` gives the bytes as a stream; `ArtifactDownload.saveTo(file)` writes
  `<file>.part`, checks the size and SHA-256 the engine sent and renames it, or deletes it and throws.

The client is tested against fake HTTP servers (`packages/xp_client/test`) and against the real engine in-process
(`apps/xpd/test/src/client`).

## The desktop app

`apps/xp_desktop` is the macOS app (Phase 15 builds its foundation; the screens of the design follow in Phases 16a to
17). The design is in `docs/design/` (see `DECISIONS.md`): the Run Sheet tokens are copied into
`lib/theme/xp_tokens.dart`, the fonts (IBM Plex Sans and Mono, OFL, licence in `assets/fonts/OFL.txt`) and the
sidebar mark are assets, and the icons are Phosphor's.

- **Layout.** `lib/<feature>/{bloc,view,widgets}` with a barrel per feature; `flutter_bloc` with `bloc_concurrency`
  (`restartable` for the streams a bloc follows, `droppable` for commands); strings in `lib/l10n/arb/app_en.arb`
  (`flutter gen-l10n` writes `lib/l10n/gen`, which is committed); light and dark themes from the tokens
  (`lib/theme/theme.dart`); `test/helpers/pump_app.dart` pumps a widget with the theme, the strings and fakes.
- **Engines.** The app shows one engine at a time: the one on this Mac ("This Mac", `http://127.0.0.1:7480`, the
  address of `xpd serve`) or a remote one added by URL and token after the same checks as `xp connect`. Their names
  and URLs are in `engines.json` in the app's Application Support folder; their tokens (kind `app`, D-06) are in the
  login Keychain under the service `ly.abdurahman.xpath.app`, account `engine.<id>`. `EngineConnectionBloc` owns the
  active engine's `EngineSession` (client, the one event stream, status, offline cache); switching engines closes the
  session, which ends every stream it gave out, and the repository subtree is keyed on the session, so it is built
  again.
- **Offline.** The repositories (`packages/xp_repositories`) cache the last answer of each list per engine
  (`<support>/cache/<engine>/*.json`) and show it first, marked as cached. When the engine stops answering the
  connection banner says so (reconnecting, then unreachable · cached), the screens keep the cached data and every
  command is disabled until the engine is back. A locked Keychain on the engine (secrets locked) and a refused
  token have their own banner.
- **The engine on this Mac heals itself.** When "This Mac" is the active engine and turns unreachable (at launch or
  later), `LocalEngineBloc` starts it once on its own: if `/health` does not answer, `EngineAgent.restart`
  (`agentRestart` in `MacosServicesChannel.swift`) unregisters an "enabled" agent and registers it again (a
  `notRegistered` or `notFound` one is registered; one waiting in Login Items is left for the owner), the app waits
  up to 30 s for `/health`, then reconnects with the token it has in the Keychain (the engine's database is the
  same, so is the token; a new `app` token is made only if the engine refuses the old one). One automatic try per
  episode (until the engine answers again), and after a failed one the next waits 1 minute, then 2, 4, up to 30;
  each step is logged (`dart:developer`, `xpath.local_engine`). The banner then reads "The engine on this Mac isn't
  running." with **Start engine** (progress, and why it failed: Login Items approval with **Open Login Items…**, a
  copy of the app without an engine, macOS refusing, no answer in 30 s); Settings ▸ About shows "Engine on this Mac:
  Running / Not running" with the same button. Remote engines keep Retry and Engines….
- **Onboarding** (the first run, or Engines ▸ Set up this Mac…): (1) registers the bundled engine as a LaunchAgent with
  `SMAppService` (label `ly.abdurahman.xpath.xpd`, plist `Contents/Library/LaunchAgents/ly.abdurahman.xpath.xpd.plist`,
  `BundleProgram` `Contents/Helpers/xpd/bin/xpd serve`) and makes the app's token with the bundled
  `xpd token create --kind app`; (2) links the bundled `xp` (`Contents/Helpers/xp/bin/xp`) into `/usr/local/bin` if the
  user can write there, else into `~/.local/bin` (no password, no dialog; another `xp` already there is left
  alone, a link into another copy of XPath is replaced); (3) checks for Xcode (`xcode-select -p`; the Command Line Tools alone do not count), git, fvm, gh and
  Shorebird in the folders the engine's service searches. The engine and `xp` are copied into the app by the
  release build (Phase 18b); a development build has neither and says so.
- **Projects and credentials.** Add project by folder (a folder picker for the local engine, a typed path on a remote
  one), then the review of the scan (apps, flavors, findings with their fixes): keep it, scan again or remove it.
  The Credentials page lists the named credentials of the engine (name, kind, account, last check, "used by N
  flavors"), and adds, renames, replaces the secret of, checks and deletes them; deleting one that flavors use lists
  them and asks first. The engine checks a credential before it keeps it, and a `.p8` key, a service account or a
  keystore can be read from a file. Under the list, each flavor of a project shows the credential it uses for each
  kind, with the check of the assignment, and a sheet to choose an existing credential or add a new one, for this
  flavor or every flavor of the app, replacing what the others have only when "Replace existing" is ticked.
- **Project overview** (Phase 16a, concept 1A): the release in flight is the hero, drawn as a rail of its run's
  stages and then its status in each store; with nothing in flight, what is live in each store. Under it, a ledger
  per app reads each flavor from local (the pubspec at the last scan) to testing (the release in flight) to live in
  the App Store and Google Play, then the names of its credentials (a click opens the sheet that assigns
  them); the console docked at the bottom follows the log of the job
  that runs (⇧⌘C hides it). The scan of the project is one click away (Scan).
- **Dispatch** (⌘N): the sheet picks a workflow, the app, flavors, platforms, the ref and the version bump, and
  previews what would run: each stage's jobs, where each lands (the engine, or the least loaded runner that can run
  it and the slot it would take) and which gates it stops at. The preview is worked out in the app
  (`DispatchPreview.plan` in `xp_repositories`) from the workflow, the runners, the gates and the credentials the
  engine returns, the same way the engine reads them; the engine still plans the run when it is dispatched. The
  button reads "Dispatch N jobs ⌘↩"; Return never dispatches.
- **Job view** (concept 2A): the run's pipeline graph over the steps and the log of one job (click a node to show
  another). The log is grouped by step, with terminal colours, a filter (⌘F), jump to error (⌘E), wrap, timestamps
  and follow (⌘↓); it resumes from the last line it holds, also after the job is resumed. Cancel (⌘.) asks first and
  says what stops, what is kept and what never starts; a failed, cancelled or interrupted job offers "Re-run all"
  (⌘R) and "Resume from <step>" (⌥⌘R, from the step picked in the step list or the first unfinished one).
- **Releases** (Phase 16b, concept 3A; Releases under the selected project, or "Open release" on the overview): the
  release shown (the one in flight, or the one picked in the toolbar) is the hero, with Merge beside it and why it
  is not open yet. Under it an App Store lane and a Google Play lane show the steps of each review, from the store
  statuses the engine keeps (Refresh asks the stores now). A store the engine cannot read (no App Store Connect key
  or Play service account for the flavor) gets "Mark approved" / "Mark live" (D-14, D-15); a rejected build offers
  "New build, same version…", which opens the run it starts. Then the timeline (what the engine keeps: the
  dispatch, each build, the last change in each store, the approvals of its runs), the release notes with "Copy for
  Slack" / "Copy for WhatsApp", the `min_version_*` reminder (the engine does not know whether a release is a forced
  update, so it says "if") and the release PR.
- **Approvals** (D-13): the needs-you bar of a project (the approval that expires first; "Review… ⇧⌘A", "Deny…"), the
  inbox (Approvals in the sidebar, with the count of what waits; Pending, Decided, Expired) and the confirmation
  sheet, the only place the app decides. The sheet says what the approval is bound to and "If you approve…"; Approve
  takes ⌘↩ (or a click) once a one-second arming delay is over, Return never approves, and an approval another device
  decided first (`409 already_decided`) or that expired ends the sheet with who decided it.
- **Notifications and the menu bar extra**: an approval that starts waiting while the app runs posts a macOS
  notification ("Review…", "Later"); the menu bar extra (`XPathTemplate`, a dot while something waits) lists every
  approval that waits and "Open XPath". Neither decides anything: "Review…" opens the confirmation sheet in the main
  window, a click on the notification opens the inbox. macOS asks for permission to notify the first time one is
  posted. Both go through `NeedsYouAlerts` in `packages/xp_macos_services` (channel `ly.abdurahman.xpath/needs_you`,
  implemented in `MacosServicesChannel.swift`; a native status item with an `NSMenu`); the tests use
  `FakeNeedsYouAlerts`.
- **macOS services** (`packages/xp_macos_services`) are interfaces with fakes (`package:xp_macos_services/testing.dart`):
  the LaunchAgent and the Keychain go through the channel `ly.abdurahman.xpath/macos_services`, implemented in
  `apps/xp_desktop/macos/Runner/MacosServicesChannel.swift`; the `xp` link, the tool check and the bundled engine are
  Dart. No test registers an agent, touches a Keychain or writes outside a temporary folder.
- **No sandbox.** XPath ships outside the Mac App Store (D-23), and it runs the bundled engine, links `xp` and checks
  tools, so the app is not sandboxed (`macos/Runner/*.entitlements`).
- **Settings** (Phase 18c; Settings in the sidebar, or XPath ▸ Settings… ⌘, in the app menu, which reaches Dart over
  the channel `ly.abdurahman.xpath/app_menu`): the app's version, the engine shown with its version and connection,
  and the engine's login item on this Mac. **Command line tool**: where `xp` is linked, or that it is not, that
  another `xp` is in the way, or that the link points into another copy of XPath (an old or moved app, a build
  folder); "Link xp" (or "Link xp again") links it as onboarding does (`CliLinker`, `FakeCliLinker` in the tests).
  A build without a bundled `xp` says so and offers nothing. **GitHub**: the engine's GitHub token, which adding a project needs: what
  GitHub says of it (the login, or why it refused it), a field to paste a new one ("Check and save"), "Import from
  GitHub CLI" (`gh auth token` on the engine machine) and "Remove token". Add project asks the engine for the token
  when it opens and after a failed add; without one (or with one GitHub refuses) it says so and "Connect GitHub…"
  opens this section with the cursor in the field.
- **Remove XPath** (Settings): a sheet with "Also delete engine data" and "Also delete Keychain items". Confirmed, it
  (1) revokes every runner of the engine on this Mac through its API while it still runs (`revokeLocalRunners`),
  (2) unregisters the engine's login item (`SMAppService.unregister`, which makes launchd stop it) and waits until
  `/health` stops answering, (3) removes the `xp` link only where it points into this app, (4) if asked and only
  once the engine stopped, deletes the engine's data folder (`~/Library/Application Support/XPath`) and the app's
  Application Support folder (engine list and cache), and (5) if asked, deletes every Keychain item whose service is
  `ly.abdurahman.xpath` or under it: the runner lists them (names only, never a value), the app's own items go
  through `SecItemDelete`, the engine's through `security delete-generic-password` (which made them). A step that
  fails is shown with what macOS or the engine said and the others still run. The sheet then offers "Move to Trash
  and quit" (`NSWorkspace.recycle` of the bundle) or "Quit XPath", and says to drag the app to the Trash when the
  Trash refuses. All of it goes through `xp_macos_services` interfaces (`EngineAgent.unregister`,
  `CliLinker.unlink`, `DataWiper`, `KeychainWiper`, `RunningApp`, `AppMenu`) with fakes; no test removes anything
  real. An engine started with `--data-dir` or `XPATH_DATA_DIR` elsewhere keeps that folder. Not built (owner,
  Goal 3): Sparkle and the appcast, and the Homebrew cask with its `zap` stanza.

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

The `gate` workflow enforces the same thresholds on Linux, where the `macos` and `golden` tests
are skipped, with one job per package. The `macos` workflow runs the packages with macOS-only tests
(and those whose code depends on the host OS) on macOS while the repository is public; on a private
repository, run `melos run test:coverage` on a Mac before merging to `main`.
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
| `golden` | Compares a widget with a golden image (`apps/xp_desktop` only). | runs on macOS only |

Because `integration` tests are skipped by default, they are not part of the coverage run.

**Goldens.** The goldens of the desktop app are drawn with the fonts it bundles (the test helper `loadAppFonts`
loads IBM Plex and Phosphor), on macOS. Linux draws text with other font hinting, so the `golden` tag has
`test_on: mac-os` in `apps/xp_desktop/dart_test.yaml`: the Linux `gate` skips them, and the `macos` workflow and the
local macOS run of `melos run test:coverage` check them. Two Macs do not draw text identically either: GitHub's
macOS runner differed from the Mac the goldens were drawn on by up to 0.03% of the pixels (408 of 1440 x 900). So
`apps/xp_desktop/test/flutter_test_config.dart` compares goldens with `TolerantGoldenComparator`
(`test/helpers/tolerant_golden_comparator.dart`), which passes a golden when at most 0.1% of its pixels differ
(about 1,300) and fails above that with the usual images in `failures/`. A changed label, colour or layout moves
more pixels than that. After a deliberate change, write them again with
`flutter test --update-goldens --tags golden` in `apps/xp_desktop`, on a Mac.

## Continuous integration

The workflows in `.github/workflows`:

- `gate.yaml`: on every pull request and every push to `main`, with no path filters, so it always reports and
  branch protection can require it. On Ubuntu it runs the full gate of CONTRIBUTING.md in jobs that run in
  parallel: `analyze` (`dart analyze --fatal-infos`, `dart format --set-exit-if-changed .`, the layer check and
  the CI matrix check), `coverage` (one job per package, each running the `test:coverage:*` script that
  `melos run test:coverage` runs it with, so it keeps its threshold), `contract` (`melos run test:contract`),
  `smoke` (`tool/e2e/smoke_bundle.sh`, which builds the `xpd` AOT bundle, starts it and checks `/health`, the
  SQLite build hook, token authentication and a clean shutdown) and `runner-offline`
  (`tool/e2e/runner_offline_e2e.sh`). The last job, `gate`, waits for all of them and fails unless every one
  passed; it is the check branch protection requires. A pull request takes about as long as the slowest package.
- `macos.yaml`: on every pull request and every push to `main`, on GitHub-hosted macOS runners, only while the
  repository is public (macOS minutes are free for public repositories only; on a private one the jobs are
  skipped, which a required check counts as passed). One `coverage` job per package with tests only macOS runs
  (`macos` and `golden` tags, the Flutter packages) or code that depends on the host OS, with the same script as
  in `gate`, and `build-desktop`, `flutter build macos --debug` of the desktop app. The last job, `macos`, waits
  for them and fails unless every one passed.

The package lists of both `coverage` matrices are written in the workflows. `dart run tool/check_ci_matrix.dart`
(in the `analyze` job) fails when a workspace package with tests is missing from the `gate` matrix, when one with
macOS-only tests is missing from the `macos` matrix, or when an entry names the wrong script: a scoped
`melos run` of a script whose filters exclude the package finds nothing and exits 0. A new package goes into the
matrix with the script its threshold comes from (`strict`, `floor` or `flutter`).
- `release.yml`: a release of XPath on every push to `main` that changes more than `site/` (see Releases and
  installation).
- `site.yaml`: on a pull request that touches `site/`, checks the website (see Website). It never deploys.
- `semantic_pull_request.yaml` checks that a pull request title follows
  [Conventional Commits](https://www.conventionalcommits.org): it becomes the squash commit and decides the
  version. `spell_check.yaml` and `license_check.yaml` cover the rest; the planning documents are ignored in
  `.github/cspell.json`.

The workspace has Flutter members, so even `dart pub get` needs the Flutter SDK; every job installs Flutter 3.47.6.
The coverage scripts run `very_good` with `--no-optimization`: its test optimizer merges the test files into one and
drops their file-level `@Tags`, so on Linux the macOS-only tests would run.

**Branch protection** for `main`: require the checks `gate` and `semantic-pull-request / build` (and `macos` once the
repository is public), and allow squash merging only, with the pull request title as the default commit message
(Settings ▸ General ▸ Pull Requests). Otherwise a single-commit pull request is merged with its commit message, and
that decides the version instead of the title. The release workflow creates tags through the API with the workflow
token; it never pushes to `main`.

## Website

`site/` is <https://xpath.abdurahman.ly>: plain HTML and CSS in `site/public`, no build step and no JavaScript. It is
served by Cloudflare Workers static assets (`site/wrangler.jsonc`: the Worker `x-path`, `not_found_handling:
"404-page"` so unknown paths get `404.html` with status 404, and the custom domain `xpath.abdurahman.ly`).

- **Pages.** `/` and `/vs/codemagic/`, plus `404.html`, `robots.txt` (search engines and AI crawlers allowed),
  `sitemap.xml` and `llms.txt`. `_redirects` sends `/install` (and `/install.sh`) to `install.sh` of the latest
  release, which is what `curl -fsSL https://xpath.abdurahman.ly/install | sh` downloads, and `/download` to the
  latest release. `_headers` sets the security headers and the cache time of `assets/`.
- **Assets.** `assets/xp-tokens.css` is a copy of `docs/design/system/project/assets/Handoff/xp-tokens.css`; copy it
  again when the tokens change (the check fails otherwise). The fonts are IBM Plex Sans and Mono from
  `apps/xp_desktop/assets/fonts`, cut to Latin and renamed "XP Sans" and "XP Mono", as the OFL asks of a modified
  copy. The screenshots in `assets/shots` are crops of the desktop goldens in `apps/xp_desktop/test/**/goldens`,
  converted to WebP; crop again after a deliberate UI change, leaving out the shortcut glyphs the test font draws as
  boxes and the sample project names.
- **Deploys.** Cloudflare Workers Builds deploys on every push to `main` that changes `site/`; nothing here holds a
  Cloudflare secret. A merge that only changes `site/` publishes no XPath release (`release.yml` ignores it), but
  its title still counts towards the version of the next release. The Worker's settings in the Cloudflare
  dashboard (Workers & Pages ▸ `x-path` ▸ Settings ▸ Build, connected to this repository):

  | Setting | Value |
  |---|---|
  | Worker name | `x-path` (must match `name` in `site/wrangler.jsonc`) |
  | Production branch | `main` |
  | Root directory | `site` |
  | Build command | none |
  | Deploy command | `npx wrangler deploy` |
  | Build watch paths | include `site/*` |
  | Branch control: builds for non-production branches | off |

  The zone `abdurahman.ly` must be on the same Cloudflare account, with no DNS record on `xpath.abdurahman.ly`
  (the custom domain creates its own).
- **Checks.** `site.yaml` runs on pull requests that touch `site/`: `node site/check.mjs` (internal links and
  fragments, image attributes, canonical URLs against the sitemap, JSON-LD that parses and a FAQPage that matches the
  visible FAQ, `_redirects`, the token copy), `html-validate` and `wrangler deploy --dry-run`. `spell_check.yaml`
  includes the pages.
- **Preview.** `cd site && npx wrangler dev` serves it as Cloudflare does (redirects, headers, the 404 page) on
  <http://localhost:8787>; any static server on `site/public` shows the pages. The current Wrangler needs Node 22.

## License

Apache-2.0. See [LICENSE](LICENSE).
