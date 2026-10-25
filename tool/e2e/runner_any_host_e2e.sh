#!/usr/bin/env bash
# A project on any git host (runner onboarding R10c, ADR 0015): its origin is a
# file:// bare repository, the engine has no GitHub token, and a runner builds it.
#
#   runner_any_host_e2e.sh
#
# builds the `xpd` and `xp` AOT bundles (`dart build cli`) and runs
# apps/xpd/tool/release_e2e.dart --mode runner-any-host, which
#
#   - starts `xpd serve` with no GitHub token and no Android SDK, and adds the
#     fixture app (tool/e2e/build_app) from a clone whose origin is a file://
#     bare repository: the engine reads it with git ls-remote, makes no GitHub
#     call, and keys it by its source key (h and 16 hex digits),
#   - pairs and starts a real `xp runner` with the Android SDK of this machine,
#     dispatches the built-in `dev-build` for Android and checks that the build
#     job ran on the runner, which fetched the commit from the file:// URL the
#     lease names (no XP_RUNNER_TEST_SOURCE_URL) into a cache named by the key,
#   - dispatches `prod-release` and checks that it is refused with the host and
#     its `git.push` step.
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
  echo "runner_any_host_e2e: $*" >&2
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

echo "Building a file:// project on a runner, with no GitHub token..."
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode runner-any-host \
    --xpd "$work/build-xpd/bundle/bin/xpd" \
    --xp "$work/build-xp/bundle/bin/xp" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run" \
    --flutter-sdk "$flutter_sdk"
) || fail "the any-host e2e failed"

echo "OK: a file:// project was added without GitHub, its dev-build ran on the runner from the URL of the lease, and prod-release was refused with the host and the step."
