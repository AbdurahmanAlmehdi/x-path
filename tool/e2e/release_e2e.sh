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
#   release_e2e.sh prod
#
# runs a production release of the fixture app from `draft` to `merged` through
# the same engine (Phase 12b): `prod-release` for Android and iOS, the owner's
# approvals through an app token, the stores (fake App Store Connect with an API
# key, fake Google Play, fake Firebase) moving from review to approved to live,
# the merge of the release pull request on a fake GitHub (a merge commit, after
# an approval of the `merge` gate), and then the checks: the state `merged`, the
# tag `v<x.y.z>+<build>` on the tip of the release branch in the fake origin,
# the owner's folder unchanged (git status, HEAD, refs and the hash of every
# file) and no secret in a stored log, the database, the output of the engine or
# the arguments of any process the engine started (PATH shims for `perl`, the
# trampoline every step process goes through, and for `git` log them).
#
# What is real and what is faked in `prod`: the engine, its database, git
# mirror, worktrees, tag and push, the Android build (a real AAB through Gradle)
# and its upload to the fake Play are real. This Mac has no signing identity and
# Apple has no fake, so `flutter build ipa` (an SDK wrapper writes a placeholder
# IPA) and `xcrun altool` (a shim prints a successful upload) are faked; the
# engine still schedules the iOS job on a Mac with Xcode, reads the IPA from the
# artifact store and calls altool as it would. `prod` needs macOS with Xcode.
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
if [[ "$mode" != "dev" && "$mode" != "prod" ]]; then
  echo "usage: release_e2e.sh dev|prod" >&2
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

if [[ "$mode" == "prod" ]]; then
  [[ "$(uname -s)" == "Darwin" ]] || fail "prod needs macOS: the iOS job of the release runs where Xcode is"
  xcode-select -p >/dev/null 2>&1 || fail "prod needs Xcode (xcode-select -p finds none)"
  command -v xcrun >/dev/null 2>&1 || fail "xcrun is not on PATH"
fi

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

if [[ "$mode" == "prod" ]]; then
  echo "Running a production release from draft to merged through the engine..."
else
  echo "Running a dev build and a production release lock through the engine..."
fi
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode "$mode" \
    --xpd "$xpd" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run" \
    --flutter-sdk "$flutter_sdk"
) || fail "the release e2e failed"

if [[ "$mode" == "prod" ]]; then
  echo "OK: the production release walked draft, building, uploaded, in_review, approved, live and merged; the tag is on the release branch in the origin, the source folder is unchanged and no secret is in the logs, the database or the process arguments."
else
  echo "OK: dev-build built the fixture through the engine (APK, manifest, Firebase release), and a second production release queued behind the first."
fi
