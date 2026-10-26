# Developing XPath

The repository layout, the dependency direction, the development setup and the Melos scripts, the test policy, continuous integration and the website. The user guide is in [docs/guide](../guide/quickstart.md); this is the reference.

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
  SQLite build hook, token authentication and a clean shutdown), `runner-offline`
  (`tool/e2e/runner_offline_e2e.sh`) and `quickstart` (`tool/e2e/quickstart_cli.sh`, the CLI path of the
  quickstart page). The last job, `gate`, waits for all of them and fails unless every one
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
