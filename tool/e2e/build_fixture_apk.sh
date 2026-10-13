#!/usr/bin/env bash
# Builds the dev APK of the fixture app (tool/e2e/build_app) through the code
# path of the engine, and checks what it stored:
#
#   - apps/xpd/tool/build_fixture_apk.dart wires what `xpd serve` wires (job
#     runner, process supervisor, SQLite repositories, Flutter resolver,
#     artifact store) against a throwaway data directory and a repository made
#     from the fixture, and runs one job: version.bump, build.android,
#     record.manifest. There is no workflow engine yet (Phase 11) to start
#     that job through the API.
#   - this script then checks, without the engine's help, that the APK is where
#     the engine says, has the size and SHA-256 it recorded, is a zip, and that
#     manifest.json lists the same SHA-256.
#
# Needs the repo's Dart and Flutter (3.47.6) first on PATH, git, perl, and the
# Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT, or the default location of
# Android Studio). The first run downloads Gradle and the Android build tools
# it does not have. Works on macOS and on x86-64 Linux (Flutter has no Android
# release compiler for Linux on ARM).
#
# The Flutter SDK is found the way the engine finds it: `.fvmrc` through fvm,
# else the cache of XPath, which downloads it. Set XPATH_E2E_FLUTTER_SDK to an
# SDK folder that already is the pinned version to skip that.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "build_fixture_apk: $*" >&2
  exit 1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
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

sdk_args=()
if [[ -n "${XPATH_E2E_FLUTTER_SDK:-}" ]]; then
  sdk_args=(--flutter-sdk "$XPATH_E2E_FLUTTER_SDK")
fi

echo "Building the dev APK of tool/e2e/build_app through the engine..."
(
  cd "$root/apps/xpd"
  dart run tool/build_fixture_apk.dart \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work" \
    ${sdk_args[@]+"${sdk_args[@]}"}
) >"$work/artifacts.txt"

# One `artifact <kind> <sha256> <size> <path>` line per stored artifact.
apk_sha=""
manifest=""
while read -r tag kind sha size path; do
  [[ "$tag" == "artifact" ]] || continue
  [[ -f "$path" ]] || fail "the $kind artifact is not at $path"
  [[ "$(wc -c <"$path" | tr -d ' ')" == "$size" ]] \
    || fail "$path is not $size bytes"
  [[ "$(sha256_of "$path")" == "$sha" ]] \
    || fail "$path does not have the SHA-256 the engine recorded"
  case "$kind" in
    apk)
      [[ "$(basename "$path")" == "dev-1.0.0+7.apk" ]] \
        || fail "unexpected APK name: $(basename "$path")"
      [[ "$(head -c 4 "$path" | od -An -tx1 | tr -d ' \n')" == "504b0304" ]] \
        || fail "$path is not a zip"
      apk_sha="$sha"
      ;;
    manifest) manifest="$path" ;;
  esac
done <"$work/artifacts.txt"

[[ -n "$apk_sha" ]] || fail "the engine stored no APK"
[[ -n "$manifest" ]] || fail "the engine stored no manifest"
for expected in \
  '"version": "1.0.0"' '"build": 7' '"tag": "v1.0.0+7"' '"dev"' \
  "\"sha256\": \"$apk_sha\"" '"flutter": "3.47.6"'; do
  grep -qF -- "$expected" "$manifest" \
    || fail "manifest.json does not contain $expected"
done

echo "OK: dev-1.0.0+7.apk ($apk_sha) is stored with the SHA-256 the engine recorded, and manifest.json lists it."
