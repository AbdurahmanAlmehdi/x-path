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
| `tool` | Repository tooling (`xp_tool`): the layer check. |
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

The data directory holds `tokens.json` for now (the database arrives in Phase 3). It is
`--data-dir`, else `$XPATH_DATA_DIR`, else `~/Library/Application Support/XPath` on macOS or
`$XDG_DATA_HOME/xpath` (`~/.local/share/xpath`) on Linux.

`tool/e2e/smoke_bundle.sh` builds the `xpd` AOT bundle with `dart build cli`, starts it on a free
port with a temporary data directory and checks `/health`, the token guard and a clean shutdown.

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
