#!/usr/bin/env bash
# A runner outlives an engine that is away for longer than a lease (runner
# onboarding R5, D-08).
#
#   runner_offline_e2e.sh
#
# builds the `xpd` and `xp` AOT bundles (`dart build cli`) and runs
# apps/xpd/tool/release_e2e.dart --mode runner-offline, which
#
#   - starts `xpd serve --slots 1` with a lease of 6 seconds
#     (XPD_TEST_LEASE_SECONDS, a test hook) against a fake GitHub, adds the
#     fixture app (tool/e2e/build_app) as a project, and pairs and starts a
#     real `xp runner` as a process of its own,
#   - gives the runner a job with a side effect (the engine's slot is taken),
#   - stops the engine with SIGSTOP, so the socket stays open and nothing
#     answers, and checks that the runner fences the job: it stops its process
#     once the lease and 15 s of grace passed without a renewal,
#   - kills the engine with SIGKILL, starts it again on the same address, and
#     checks that the same runner process reconnects by itself within 60 s and
#     that the job follows the loss rule: it waits for a resume and is never
#     run again by itself.
#
# Takes about two minutes. Needs the repo's Dart and Flutter first on PATH,
# git, perl and pgrep; no Android SDK, Xcode or store. Works on macOS and on
# Linux.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "runner_offline_e2e: $*" >&2
  exit 1
}

for tool in dart flutter git perl pgrep; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on PATH"
done

flutter_sdk="${XPATH_E2E_FLUTTER_SDK:-}"
if [[ -z "$flutter_sdk" ]]; then
  flutter_bin="$(command -v flutter)"
  flutter_sdk="$(cd "$(dirname "$flutter_bin")/.." && pwd -P)"
fi

build() {
  local app="$1" name="$2"
  echo "Building the $name bundle..."
  (cd "$root/apps/$app" && dart build cli -t "bin/$name.dart" -o "$work/build-$name" >"$work/build-$name.log" 2>&1) \
    || { cat "$work/build-$name.log" >&2; fail "dart build cli failed for $name"; }
  [[ -x "$work/build-$name/bundle/bin/$name" ]] || fail "no executable at $work/build-$name/bundle/bin/$name"
}
build xpd xpd
build xp xp

echo "Taking the engine away from a runner that holds a job..."
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode runner-offline \
    --xpd "$work/build-xpd/bundle/bin/xpd" \
    --xp "$work/build-xp/bundle/bin/xp" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run" \
    --flutter-sdk "$flutter_sdk"
) || fail "the runner offline e2e failed"

echo "OK: the runner fenced the job whose lease ran out while the engine was stopped, reconnected by itself within 60 s of the engine coming back, and the job waits for a resume."
