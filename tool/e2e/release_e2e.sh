#!/usr/bin/env bash
# Runs a release of the fixture app (tool/e2e/build_app) through a real engine,
# against fake stores.
#
#   release_e2e.sh dev
#
# builds the `xpd` AOT bundle (`dart build cli`) and runs
# apps/xpd/tool/release_e2e.dart, which
#
#   - starts a fake Firebase App Distribution and a fake GitHub on loopback
#     ports, and `xpd serve` pointed at them (XPD_TEST_*; its secrets in a file,
#     never in the Keychain), in a temporary data directory,
#   - adds the fixture as a project over HTTP, saves a Firebase service
#     account and dispatches the built-in `dev-build` workflow for Android,
#   - waits for the job and checks that it stored an APK and a manifest.json,
#     that Firebase received exactly that APK as the version of the job, and
#   - dispatches `prod-release` twice and checks that the second queues behind
#     the first (the project lock, D-11) and runs once the first is cancelled.
#
# `release_e2e.sh prod` (the whole production release against fake stores and
# a fake GitHub, up to the merged pull request) is Phase 12b.
#
# Needs the repo's Dart and Flutter (3.47.6) first on PATH, git, perl, and the
# Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT, or the default location of
# Android Studio). The first run downloads Gradle and the Android build tools
# it does not have. Works on macOS and on x86-64 Linux (Flutter has no Android
# release compiler for Linux on ARM). Takes a few minutes. Set
# XPATH_E2E_FLUTTER_SDK to an SDK folder that already is the pinned version to
# skip the search for it (fvm, then XPath's cache, which downloads it).
set -euo pipefail

mode="${1:-}"
if [[ "$mode" != "dev" ]]; then
  echo "usage: release_e2e.sh dev" >&2
  echo "(release_e2e.sh prod arrives with Phase 12b)" >&2
  exit 64
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "release_e2e: $*" >&2
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
echo "Android SDK: $sdk"

# The Flutter on PATH is the pinned one in this repo; link it for the engine
# unless the caller says which SDK to use.
flutter_sdk="${XPATH_E2E_FLUTTER_SDK:-}"
if [[ -z "$flutter_sdk" ]]; then
  flutter_bin="$(command -v flutter)"
  flutter_sdk="$(cd "$(dirname "$flutter_bin")/.." && pwd -P)"
fi

echo "Building the xpd bundle..."
(cd "$root/apps/xpd" && dart build cli -t bin/xpd.dart -o "$work/build" >"$work/build.log" 2>&1) \
  || { cat "$work/build.log" >&2; fail "dart build cli failed"; }
xpd="$work/build/bundle/bin/xpd"
[[ -x "$xpd" ]] || fail "no executable at $xpd"

echo "Running a dev build and a production release lock through the engine..."
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode "$mode" \
    --xpd "$xpd" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run" \
    --flutter-sdk "$flutter_sdk"
) || fail "the release e2e failed"

echo "OK: dev-build built the fixture through the engine (APK, manifest, Firebase release), and a second production release queued behind the first."
