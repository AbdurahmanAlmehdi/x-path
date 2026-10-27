#!/usr/bin/env bash
# iOS builds of a flavored app on a Linux runner through omarchy-apple-dev
# (iOS on Linux 3b, ADR 0014; iOS flavors on Linux, Phase 3), with the
# omarchy-apple-dev scripts and tools as stubs.
#
#   runner_ios_linux_e2e.sh
#
# builds the `xpd` and `xp` AOT bundles (`dart build cli`) and runs
# apps/xpd/tool/release_e2e.dart --mode runner-ios-linux, which
#
#   - starts `xpd serve` in a temporary data directory against a fake GitHub
#     and a fake App Store Connect, and adds an iOS-only copy of the fixture
#     app (tool/e2e/build_app without Android, given the iOS flavors dev and
#     prod: a scheme, a Release-<flavor> configuration with its own bundle id
#     and lib/main_<flavor>.dart each, and a single-size icon) as a project,
#   - writes a stub omarchy-apple-dev checkout (flutter/setup.sh, build.sh and
#     ship.sh log what they get and write what the real ones would) and stubs
#     of the tools the probe looks for, and starts a real `xp runner` with
#     XP_IOS_LINUX_DIR set, which reports `ios-linux`,
#   - saves an App Store Connect key and an Apple Distribution identity for
#     each flavor and runs a workflow of checkout, version bump, `build.ios`,
#     `symbols.archive` and `record.manifest` for both flavors in one run
#     (the runner has 2 slots), then for dev again,
#   - checks that every build ran on the runner without being narrowed to a
#     Mac, that build.sh got FLAVOR and TARGET and built the two flavors of
#     the run in separate directories, that setup.sh prepared the dedicated
#     Flutter install once, that ship.sh got no ASC_ENTITLEMENTS_PATH, signed
#     the configuration build.sh recorded with the profile the engine made for
#     the flavor and never saw the App Store Connect key, that the IPA, the
#     dSYMs and a manifest naming the omarchy-apple-dev commit reached the
#     engine, and that the runner left no secret behind.
#
# Linux only (a Mac builds iOS with Xcode). Needs the repo's Dart first on
# PATH, git and perl. No Flutter SDK, Xcode.xip or Apple account is used.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "runner_ios_linux_e2e: $*" >&2
  exit 1
}

[[ "$(uname -s)" == Linux ]] || fail "needs Linux: a Mac builds iOS with Xcode"
for tool in dart git perl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on PATH"
done

build() {
  local app="$1" name="$2"
  echo "Building the $name bundle..."
  (cd "$root/apps/$app" && dart build cli -t "bin/$name.dart" -o "$work/build-$name" >"$work/build-$name.log" 2>&1) \
    || { cat "$work/build-$name.log" >&2; fail "dart build cli failed for $name"; }
  [[ -x "$work/build-$name/bundle/bin/$name" ]] || fail "no executable at $work/build-$name/bundle/bin/$name"
}
build xpd xpd
build xp xp

echo "Building the iOS app on a Linux runner with stubbed omarchy-apple-dev..."
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode runner-ios-linux \
    --xpd "$work/build-xpd/bundle/bin/xpd" \
    --xp "$work/build-xp/bundle/bin/xp" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run"
) || fail "the runner iOS on Linux e2e failed"

echo "OK: build.ios built the flavors dev and prod on the Linux runner through omarchy-apple-dev's scripts with FLAVOR and TARGET, in separate directories, signed with the identity and the profile the engine made for each, and the IPA and the dSYMs reached the engine."
