---
name: xpath-contributing
description: Change the XPath codebase itself (the xpd engine, the xp CLI and xp mcp, the runner, the macOS app, the packages and tooling of the AbdurahmanAlmehdi/x-path repository). Use when adding or fixing code, tests, API endpoints, database migrations, desktop screens or ADRs in XPath, when running its local gate or end-to-end scripts, or when writing a pull request title for it. Covers the layer rules, the coverage policy, test tags and fakes, migrations with snapshot goldens, openapi contract tests, desktop conventions, and the safety rules for secrets.
license: Apache-2.0
---

# Contributing to XPath

XPath releases other people's apps with their signing keys, so every change comes with tests and
nothing ever talks to a real store from a test. Read `CONTRIBUTING.md` first; the `docs/reference`
pages named below hold the details, so read them instead of guessing.

## Set up

The repository pins Flutter and Dart in `.fvmrc`. From the repository root:

```sh
fvm install
export PATH="$PWD/.fvm/flutter_sdk/bin:$HOME/.pub-cache/bin:$PATH"
dart pub global activate melos
dart pub global activate very_good_cli 1.5.0
dart pub get
```

Put that `PATH` line in every shell (and every command you run): an older Dart elsewhere on the
`PATH` will not resolve the workspace. Every member needs the Flutter SDK to resolve; there is
no Dart-only `dart pub get`. `.fvm` is gitignored; never commit it.

## Where code goes

| Path | What it is |
|---|---|
| `packages/xp_api` | Models, error codes and events shared by every client and the engine; `openapi.yaml` |
| `packages/xp_engine` | Domain and application logic. Framework-free; defines interfaces only |
| `packages/xp_adapters` | Implements the engine's interfaces: SQLite, git, GitHub, stores, processes |
| `packages/xp_secrets` | The secret store: Keychain, encrypted file, log masking |
| `packages/xp_client` | HTTP and WebSocket client of the API |
| `packages/xp_repositories` | Repositories for the desktop app, on `xp_client` |
| `packages/xp_macos_services` | Flutter package for macOS platform services, with fakes |
| `apps/xpd` | Engine entrypoint: wires implementations, owns the HTTP handlers |
| `apps/xp` | The `xp` CLI, `xp mcp` and `xp runner` |
| `apps/xp_desktop` | The macOS app (Flutter) |
| `tool` | `check_layers.dart`, `tool/e2e` (scripts, fixtures, fake store servers), `tool/release` |

The dependency direction is enforced on every `import`/`export` in `lib/`, `test/`, `bin/` and
`integration_test/` and on every `pubspec.yaml`. The rules are in
`tool/lib/src/layer_rules.dart`:

- `xp_engine` depends on `xp_api` only, plus an allowlist of pure packages (`collection`,
  `crypto`, `equatable`, `meta`, `yaml`). Adding to that list is a reviewed decision.
- `xp_adapters` and `xp_secrets` may use `xp_engine` and `xp_api`.
- `xp_client` uses `xp_api`; `xp_repositories` uses `xp_client` and `xp_api`.
- `xp` uses `xp_client` for everything it asks the engine, plus `xp_secrets`, and the engine's
  step runner and adapters for `xp runner`.
- `xpd` wires the engine, adapters and secret stores.
- The desktop app never imports `xp_engine`, `xp_adapters` or `xp_secrets`.

```sh
dart run tool/check_layers.dart
```

So: interfaces and logic in `xp_engine`, implementations in `xp_adapters` or `xp_secrets`, HTTP
handlers in `apps/xpd`, CLI commands in `apps/xp`, MCP tools in `apps/xp/lib/src/mcp` (only
`dart_mcp_adapter.dart` imports `dart_mcp`).

## Tests

Tests are part of the change, not a follow-up.

**Coverage** (`melos run test:coverage`, enforced in CI):

| Threshold | Packages |
|---|---|
| 100% lines | `xp_api`, `xp_client`, `xp_engine`, `xp_repositories`, and every bloc |
| 90% lines | everything else |

Coverage counts the files tests import, so keep each package's barrel (`lib/<name>.dart`)
exporting everything. `*.g.dart` is excluded.

**Fakes, never the real thing.** Store APIs, GitHub and Shorebird are tested against the fake
servers in `tool/e2e/fake_stores` (`xp_fake_asc`, `xp_fake_play`, `xp_fake_firebase`) or fake
HTTP servers. Processes go through a fake `ProcessRunner`; macOS services through the fakes in
`package:xp_macos_services/testing.dart`. Never use real credentials, real store accounts or a
real Keychain; no test installs a LaunchAgent or a systemd unit or writes outside a temporary
folder. Parsers of tool output are tested against captured output kept as fixtures.

**Tags** (declared in every package's `dart_test.yaml`):

| Tag | Meaning | Default run |
|---|---|---|
| `contract` | API responses checked against `openapi.yaml`; lives in `test/contract/` | runs |
| `process` | spawns real child processes | runs |
| `macos` | needs macOS (Keychain, SMAppService, ...) | macOS only |
| `integration` | needs external tools or services | skipped; `dart test --run-skipped -t integration` |
| `golden` | widget golden images (`apps/xp_desktop` only) | macOS only |

GitHub CI runs on Linux only. Run `melos run test:coverage` on a Mac before merging, so the
`macos` and `golden` tests run.

## The full local gate

```sh
dart analyze --fatal-infos && dart format --set-exit-if-changed . \
  && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract \
  && tool/e2e/smoke_bundle.sh
```

One package while you work: `very_good dart test` (Dart) or `very_good test` (Flutter) in its
folder, or `dart test path/to/file_test.dart`.

End-to-end scripts in `tool/e2e/` run whole flows against the fake stores; run the ones your
change touches:

| Script | Covers | Needs |
|---|---|---|
| `smoke_bundle.sh` | the AOT `xpd` bundle starts, `/health`, database, token guard, clean shutdown | `curl`, `perl` |
| `release_e2e.sh dev` | `dev-build` for Android through the real engine to a fake Firebase | Android SDK; minutes |
| `release_e2e.sh prod` | a whole production release from `draft` to `merged`, no secret in any log, argv or file | macOS with Xcode, Android SDK; several minutes |
| `mcp_gate_e2e.sh` | `xp mcp` dispatches, stops at a gate, gets `403` on approve | about half a minute |
| `quickstart_cli.sh` | the CLI path of `docs/guide/quickstart.md`: connect, status, doctor, a `file://` project, a green `test` run (CI runs it) | Flutter; about a minute |
| `runner_loss_e2e.sh` | a runner killed mid-job: the 90 second lease rule, no secret left | about four minutes |
| `runner_build_e2e.sh` | a build job leased to a runner, upload from the engine | Android SDK on the runner side |
| `build_fixture_apk.sh` | builds the fixture app's APK through a job | Android SDK |

## Changes with extra rules

- **API change**: update `packages/xp_api/openapi.yaml` and add a contract test in the
  `test/contract/` of `apps/xpd` (or `xp_api`). Add the method to `xp_client` (100% coverage).
  `melos run test:contract` runs only packages with a `test/contract/` folder.
- **Database change**: a new migration appended to `packages/xp_adapters/lib/src/sqlite/migrations.dart`,
  never an edit of a released one, plus its snapshot golden `test/src/sqlite/snapshots/v<N>.sql`
  (ADR 0002):

  ```sh
  cd packages/xp_adapters && UPDATE_GOLDENS=1 dart test test/src/sqlite/migrations_test.dart
  ```

  Before migrating an existing database, `xpd` copies it to `xpath.db.bak-v<old version>`.
- **Scanner**: fixtures in `tool/e2e/fixtures`, goldens rewritten with
  `UPDATE_GOLDENS=1 dart test test/scan/fixtures_test.dart` in `packages/xp_engine`. Review the diff.
- **Workflow steps**: the step lives under `packages/xp_engine/lib/src/steps`, is registered in
  the `StepRegistry` of `apps/xpd/lib/src/cli/serve_command.dart` (and of
  `apps/xp/lib/src/runner/runner_steps.dart` if a runner may run it), and gets its `with` keys and
  planner in `StepPlanners` (`packages/xp_engine/lib/src/dispatch/step_planners.dart`), which is
  also what `GET /workflows/schema` and validation read. Decide whether it has a side effect
  (`sideEffectOf`, `alreadyDone`) and whether only the engine may run it
  (`RemoteStepPolicy`). The built-in workflow documents (in `packages/xp_engine/lib/src/workflows`) must keep engine-only steps out of
  build jobs (ADR 0010).
- **Against an ADR**: a decision that goes against one in `docs/adr/` needs a new ADR
  (`NNNN-title.md`: Status, Date, Context, Decision, ...) in the same pull request.

## The desktop app

- `lib/<feature>/{bloc,view,widgets}` with a barrel per feature; `flutter_bloc` with
  `bloc_concurrency` (`restartable` for streams a bloc follows, `droppable` for commands).
- It talks to the engine only through `packages/xp_repositories`; macOS services only through
  `xp_macos_services` interfaces.
- Strings in `lib/l10n/arb/app_en.arb`; run `flutter gen-l10n`, and commit `lib/l10n/gen`.
- Theme from the tokens in `lib/theme/xp_tokens.dart`; design in `docs/design/`.
- Widget tests pump with `test/helpers/pump_app.dart`.
- Goldens are drawn on macOS with the bundled fonts. After a deliberate UI change:

  ```sh
  cd apps/xp_desktop && flutter test --update-goldens --tags golden
  ```

## Safety rules

- A secret never goes in process arguments, logs, events, API responses or files outside the
  engine's data directory. Pass it by environment variable name or as a 0600 file
  (`secretEnvironment`, `secretFiles`), and give every new secret value to the log masker.
- Never call a real store, GitHub, Shorebird or a real Keychain from a test.
- Never weaken a gate: only `app` and `cli` tokens decide approvals; `mcp` and `runner` tokens get
  `403`. A new route is closed to `runner` tokens unless opened on purpose (ADR 0011).
- A step with a side effect is never repeated by the engine on its own; it implements
  `alreadyDone`.
- The engine writes nothing to a user's repository except release-model git changes.

Security problems are reported privately (`SECURITY.md`), not in issues.

## Pull requests

Work on a branch; `main` is protected. One change per pull request. Pull requests are
squash-merged, the title becomes the commit on `main`, and **every merge to `main` publishes a
release whose version the title decides** (Conventional Commits; the table is in
`CONTRIBUTING.md`):

| Title starts with | Version change |
|---|---|
| `feat:` | minor |
| `fix:`, `perf:` | patch |
| `feat!:` or a `BREAKING CHANGE:` footer | major |
| `docs:`, `test:`, `ci:`, `chore:`, `refactor:`, `build:`, `style:` | patch |

Write the title as what changes for a user, in the present tense:
`feat: retry Play uploads after a 503`. Every pull request needs an approving review and green
CI. The spell check (`.github/cspell.json`) reads every Markdown file, the guide and the reference
included; add real words it does not know to its `words` list.

## Where to read more

- `CONTRIBUTING.md`: the process and the PR title table.
- `docs/reference/development.md`: "Repository layout", "Dependency direction", "Development
  setup", "Testing" and "Continuous integration"; the other `docs/reference` page of the area
  you change. A user-facing change also updates its page in `docs/guide`.
- `docs/adr/`: the decisions; `docs/plan/` for the phases and D-numbers the code cites.
