#!/usr/bin/env bash
# Losing a runner in the middle of a job (Phase 14b, D-08, D-09): the engine takes
# the job back after the lease lapses, and the restarted runner leaves no secret
# behind.
#
#   runner_loss_e2e.sh
#
# builds the `xpd` and `xp` AOT bundles (`dart build cli`) and runs
# apps/xpd/tool/release_e2e.dart --mode runner-loss, which
#
#   - starts `xpd serve --slots 1` in a temporary data directory against a fake
#     GitHub (XPD_TEST_*; its secrets in a file, never in the Keychain) and adds
#     the fixture app (tool/e2e/build_app) as a project, with a made-up
#     keystore credential (a `keytool` shim accepts it),
#   - pairs and starts a real `xp runner` as a process of its own, with a data
#     directory of its own on this machine (its credential in an encrypted file,
#     never in a Keychain); the repository the engine names is the bare
#     repository that plays GitHub, which the runner fetches with git into its
#     own bare cache (the URL is replaced by XP_RUNNER_TEST_SOURCE_URL, a test
#     hook, since there is no SSH key to read from),
#   - dispatches a workflow whose two jobs run on the runner (the only slot of
#     the engine is taken by a long job): each checks out the commit, receives
#     the keystore as a file and its password, and sleeps; one declares a side
#     effect, one does not,
#   - kills the runner with SIGKILL, waits for the lease to lapse (the production
#     timing: 90 seconds and the sweep) and checks the loss rule: the job with a
#     side effect is waiting_for_resume (never repeated by itself), the other is
#     queued again,
#   - starts the runner again and checks that no secret file, temporary keychain
#     or process is left, then resumes the job, cancels it, and checks that the
#     process group is gone and the secret files with it.
#
# Takes about four minutes (the lease is the production 90 seconds). Needs the
# repo's Dart and Flutter (3.47.6) first on PATH, git, perl and pgrep; no
# Android SDK, Xcode or store. Works on macOS and on Linux.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "runner_loss_e2e: $*" >&2
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

echo "Killing a runner in the middle of a job..."
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode runner-loss \
    --xpd "$work/build-xpd/bundle/bin/xpd" \
    --xp "$work/build-xp/bundle/bin/xp" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run" \
    --flutter-sdk "$flutter_sdk"
) || fail "the runner loss e2e failed"

echo "OK: the runner was killed in the middle of two jobs; after the 90 second lease the engine took them back (waiting_for_resume for the step with a side effect, queued for the other), and the restarted runner left no secret file, temporary keychain or process behind."
