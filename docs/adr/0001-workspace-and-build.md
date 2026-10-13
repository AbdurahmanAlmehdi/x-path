# ADR 0001: Workspace and build

- **Status:** Accepted
- **Date:** 2026-10-13
- **Phase:** 0 (decides the shape of Phase 1)

## Context

The plan puts every package and app, including the Flutter macOS app, in one Dart pub
workspace driven by Melos 8, measures coverage with `very_good test`, and ships the engine as
an AOT bundle for macOS and Linux. Three things were unproven: whether the Flutter app can
share the workspace resolution, whether coverage works for a workspace member, and whether
`dart build cli` cross-compiles to Linux with the `sqlite3` build hook.

## Decision

1. **One workspace.** `apps/xp_desktop` is a normal workspace member (`resolution: workspace`).
   No separate workspace with path dependencies is needed.
2. **Toolchain pin.** The repo pins Flutter 3.47.6 (Dart 3.13.5) in `.fvmrc`. The machine's
   default SDK can be older (this Mac has Dart 3.10.1 on `PATH`), so every command, including
   globally activated tools (`melos`, `very_good`), runs with `.fvm/flutter_sdk/bin` first on
   `PATH`. Global pub executables use whichever `dart` is on `PATH`.
3. **Melos 8** is a root `dev_dependency` (resolved 8.9.0) configured under `melos:` in the root
   `pubspec.yaml`. The global `melos` delegates to it.
4. **Coverage** uses `very_good test --coverage --min-coverage <n>` per package (very_good_cli
   1.5.0); it writes `coverage/lcov.info` inside the member.
5. **Bundles** use `dart build cli`, which runs the `sqlite3` hook and emits
   `bundle/bin/<exe>` plus `bundle/lib/libsqlite3.{dylib,so}`. Cross-compiling from macOS to
   `linux-x64` and `linux-arm64` works, so Linux bundles do not need a Linux build host.
   CI still runs the Linux test suite on Linux.

## Proof

Scratch workspace with a pure Dart member depending on `sqlite3: ^3.0.0` and a
`flutter create --platforms=macos` member, both `resolution: workspace`:

```sh
export PATH=$PWD/.fvm/flutter_sdk/bin:$HOME/.pub-cache/bin:$PATH
dart pub get                                    # root: resolves Dart + Flutter members together
(cd apps/ui && flutter test)                    # All tests passed!
dart run melos --version                        # 8.9.0
(cd packages/eng && very_good test --coverage --min-coverage 100)   # coverage/lcov.info written
dart build cli -t bin/eng.dart -o out-host && out-host/bundle/bin/eng          # sqlite 3.53.4
dart build cli -t bin/eng.dart --target-os linux --target-arch x64   -o out-linux
dart build cli -t bin/eng.dart --target-os linux --target-arch arm64 -o out-linux-arm
docker run --rm --platform linux/amd64 -v $PWD/out-linux/bundle:/b debian:bookworm-slim /b/bin/eng      # sqlite 3.53.4
docker run --rm --platform linux/arm64 -v $PWD/out-linux-arm/bundle:/b debian:bookworm-slim /b/bin/eng  # sqlite 3.53.4
```

## Consequences

- Phase 1 keeps the single-workspace layout from the plan.
- Phase 18a can build all four engine bundles on one macOS runner; a Linux job still smoke-tests
  the Linux bundles.
- `dart compile exe` stays unused (it skips build hooks).
