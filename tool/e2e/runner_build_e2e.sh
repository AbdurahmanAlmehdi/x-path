#!/usr/bin/env bash
# A build job of a built-in workflow on a runner (Phase 14b, ADR 0009, 0010).
#
#   runner_build_e2e.sh
#
# builds the `xpd` and `xp` AOT bundles (`dart build cli`) and runs
# apps/xpd/tool/release_e2e.dart --mode runner-build, which
#
#   - starts `xpd serve` in a temporary data directory against a fake GitHub and
#     a fake Firebase (XPD_TEST_*; its secrets in a file, never in the Keychain),
#     with an environment that has no Android SDK, so the engine cannot build
#     Android, and adds the fixture app (tool/e2e/build_app) as a project,
#   - pairs and starts a real `xp runner` with a data directory of its own and
#     the Android SDK of this machine, with the pinned Flutter SDK in its cache,
#   - dispatches the built-in `dev-build` for Android: its `check` job and its
#     `upload` job run on the engine, its `build` job goes to the runner, which
#     fetches the commit from the bare repository that plays GitHub (the URL is
#     replaced by XP_RUNNER_TEST_SOURCE_URL, a test hook), bumps the version,
#     builds a real APK with Gradle and uploads it and its manifest,
#   - checks where each job ran, that the APK in the engine's store is the one
#     the runner built, that the fake Firebase received it from the engine, and
#     that the runner left no worktree, work folder or secret behind.
#
# Needs the repo's Dart and Flutter (3.47.6) first on PATH, git, perl, and the
# Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT, or the default location of
# Android Studio). Takes a few minutes. Set XPATH_E2E_FLUTTER_SDK to an SDK
# folder that already is the pinned version to skip the search for it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "runner_build_e2e: $*" >&2
  exit 1
}

for tool in dart flutter git perl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on PATH"
done

sdk=""
for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
  "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
  if [[ -n "$candidate" && -d "$candidate" ]]; then
    sdk="$candidate"
    break
  fi
done
[[ -n "$sdk" ]] || fail "no Android SDK: set ANDROID_HOME or install Android Studio"
# The runner finds it by the variable; the engine is started without it.
export ANDROID_HOME="$sdk"

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

echo "Building the fixture app on a runner..."
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode runner-build \
    --xpd "$work/build-xpd/bundle/bin/xpd" \
    --xp "$work/build-xp/bundle/bin/xp" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run" \
    --flutter-sdk "$flutter_sdk"
) || fail "the runner build e2e failed"

echo "OK: the build job of dev-build ran on the runner (its own checkout, a real APK) while the check and the Firebase upload ran on the engine, and the runner left nothing behind."
