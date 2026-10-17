# Contributing to XPath

Thanks for helping. XPath releases other people's apps with their signing keys, so changes are held
to a high bar: every change comes with tests, and nothing ever talks to a real store from a test.

## Before you start

- For anything bigger than a small fix, open an issue first and describe the change. It saves you
  from building something that does not fit.
- Read the [README](README.md): the repository layout, the dependency direction between packages,
  and the coverage policy are enforced by CI.
- Architecture decisions live in [`docs/adr/`](docs/adr). A change that goes against one needs a new
  ADR in the same pull request.
- Security problems are not reported in issues. See [SECURITY.md](SECURITY.md).

## Set up

The repo pins Flutter and Dart in `.fvmrc`. Install [fvm](https://fvm.app), then from the repo root:

```sh
fvm install
export PATH="$PWD/.fvm/flutter_sdk/bin:$HOME/.pub-cache/bin:$PATH"
dart pub global activate melos
dart pub global activate very_good_cli 1.5.0
dart pub get
```

Keep that `PATH` line in every shell you use for this repo; an older Dart elsewhere on your `PATH`
will not resolve the workspace.

## Make the change

- Work on a branch and open a pull request against `main`. Direct pushes to `main` are blocked.
- Keep each pull request to one change. Large features are split into pull requests that each build
  and pass on their own.
- Follow the existing code: its naming, structure and test layout. Dependencies between packages
  follow the rules in `tool/lib/src/layer_rules.dart`; `dart run tool/check_layers.dart` checks
  them.
- `packages/xp_engine` stays framework-free. Implementations go in `xp_adapters` or `xp_secrets`,
  HTTP handlers in `apps/xpd`, the CLI in `apps/xp`.
- An API change updates `packages/xp_api/openapi.yaml` and adds a contract test.
- A database change is a new migration with its snapshot golden (ADR 0002).

## Test it

Tests are part of the change, not a follow-up.

- Coverage: 100% of lines in `xp_api`, `xp_client`, `xp_engine`, `xp_repositories` and every bloc;
  at least 90% everywhere else.
- Store APIs, GitHub and Shorebird are tested against the fakes in `tool/e2e/fake_stores` or fake
  HTTP servers. Never use real credentials, real store accounts or a real Keychain in a test.
- Tests that need macOS or real processes carry the tags described in the README.
- Desktop goldens are drawn on macOS. After a deliberate UI change, update them with
  `flutter test --update-goldens --tags golden` in `apps/xp_desktop`.

Run the full check before you push:

```sh
dart analyze --fatal-infos && dart format --set-exit-if-changed . \
  && dart run tool/check_layers.dart && melos run test:coverage && melos run test:contract \
  && tool/e2e/smoke_bundle.sh
```

The end-to-end scripts in `tool/e2e/` (`release_e2e.sh dev`, `release_e2e.sh prod`,
`mcp_gate_e2e.sh`, `runner_loss_e2e.sh`) cover whole releases against the fake stores. Run the ones
your change touches.

## Pull request titles

Pull requests are squash-merged, and the title becomes the commit on `main`. Every merge to `main`
publishes a release, and the title decides its version, so use
[Conventional Commits](https://www.conventionalcommits.org):

| Title starts with | Version change |
|---|---|
| `feat:` | minor (1.4.2 → 1.5.0) |
| `fix:`, `perf:` | patch (1.4.2 → 1.4.3) |
| `feat!:` or a `BREAKING CHANGE:` footer | major (1.4.2 → 2.0.0) |
| `docs:`, `test:`, `ci:`, `chore:`, `refactor:`, `build:`, `style:` | patch |

Write the title as a short description of what changes for a user, in the present tense:
`feat: retry Play uploads after a 503`, not `feat: updated stuff`.

## Review

Every pull request needs an approving review and green CI before it merges. A reviewer checks that
the change does what the title says, that it is tested, and that no secret can reach a log, a
process argument or a file outside the engine's data directory.

## License

By contributing you agree that your contribution is licensed under the
[Apache License 2.0](LICENSE), the license of this repository.
