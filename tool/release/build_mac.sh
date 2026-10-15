#!/usr/bin/env bash
# Builds XPath.app for this Mac, with the engine (`xpd`) and the CLI (`xp`)
# inside, signed for a local install.
#
#   tool/release/build_mac.sh [--reuse-bundles] [--install]
#
# Steps:
#   1. tool/release/bundles.sh builds the `xpd` and `xp` bundles for this
#      Mac (and the Linux runner bundles the engine hands to runners),
#      unless --reuse-bundles takes the ones already in build/release.
#   2. `flutter build macos --release` builds apps/xp_desktop.
#   3. The bundles go into XPath.app/Contents/Helpers/xpd/{bin,lib} and
#      Contents/Helpers/xp/{bin,lib}: the LaunchAgent plist runs
#      Contents/Helpers/xpd/bin/xpd (BundleProgram), and the app links
#      Contents/Helpers/xp/bin/xp into PATH. The runner archives go into
#      Contents/Resources/runners (Helpers may hold only code).
#   4. Every Mach-O inside is signed, deepest first, then the frameworks,
#      then the app (Release entitlements), all with the Hardened Runtime
#      and no secure timestamp (a local build needs none). The helpers get
#      Helpers.entitlements: the Dart AOT runtime needs
#      allow-unsigned-executable-memory under the Hardened Runtime.
#   5. `codesign --verify --deep --strict` checks the app, and the signed
#      helpers must print their --version.
#
# The result is dist/XPath.app. --install then quits a running XPath and
# replaces /Applications/XPath.app with it. It does nothing else: it does
# not open the app, register the engine's LaunchAgent or link `xp`.
#
# Signing identity: $XPATH_SIGN_IDENTITY, by default the owner's
# "Apple Development: Abdurahman Ibrahem (L7UMZN6DL6)" (team AFBD5TBR5U).
# A codesign that waits more than 60 s (a Keychain dialog) is stopped.
#
# Not done here (owner, Goal 3): Developer ID signing, notarization,
# stapling and the DMG.
#
# Needs the repo's Flutter (.fvm/flutter_sdk/bin) first on PATH and
# `dart pub get` done.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
identity="${XPATH_SIGN_IDENTITY:-3B9E9C2FB4D94EFC7AC367C68CF1FC077EBB799F}"
bundle_id="ly.abdurahman.xpath"
dist="$root/dist"
app="$dist/XPath.app"
installed="/Applications/XPath.app"
sign_timeout=60
reuse=false
install=false

die() {
  echo "build_mac: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reuse-bundles) reuse=true; shift ;;
    --install) install=true; shift ;;
    -h | --help) sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done

[[ "$(uname -s)" == Darwin ]] || die "build XPath.app on a Mac"
case "$(uname -m)" in
  arm64) host=macos-arm64 ;;
  x86_64) host=macos-x64 ;;
  *) die "unsupported machine $(uname -m)" ;;
esac
command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH"

bundles="$root/build/release/bundles/$host"
if [[ "$reuse" == false ]]; then
  "$root/tool/release/bundles.sh" --targets "$host linux-x64 linux-arm64"
fi
for helper in xpd xp; do
  [[ -x "$bundles/$helper/bin/$helper" ]] \
    || die "no $helper bundle in $bundles; run without --reuse-bundles"
done

echo "Building XPath.app (flutter build macos --release)..."
(cd "$root/apps/xp_desktop" && flutter build macos --release)
built="$root/apps/xp_desktop/build/macos/Build/Products/Release/XPath.app"
[[ -d "$built" ]] || die "flutter build did not make $built"

rm -rf "$app"
mkdir -p "$dist"
ditto "$built" "$app"
helpers="$app/Contents/Helpers"
mkdir -p "$helpers"
for helper in xpd xp; do
  mkdir -p "$helpers/$helper"
  ditto "$bundles/$helper/bin" "$helpers/$helper/bin"
  ditto "$bundles/$helper/lib" "$helpers/$helper/lib"
done
# Contents/Helpers holds only signed code; the runner archives the engine
# hands to runners that update are data (runnerBundleRoots finds them).
if [[ -d "$bundles/xpd/runners" ]]; then
  ditto "$bundles/xpd/runners" "$app/Contents/Resources/runners"
fi

# Runs codesign, but stops it when it waits longer than $sign_timeout
# seconds: that is a Keychain dialog nobody answers.
run_codesign() {
  local log status waited=0
  log="$(mktemp)"
  codesign "$@" >"$log" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if ((waited >= sign_timeout)); then
      kill "$pid" 2>/dev/null || true
      cat "$log" >&2
      rm -f "$log"
      die "codesign waited more than $sign_timeout s (a Keychain dialog?); stopped"
    fi
    sleep 1
    waited=$((waited + 1))
  done
  status=0
  wait "$pid" || status=$?
  if ((status != 0)); then
    cat "$log" >&2
    rm -f "$log"
    die "codesign $* failed (exit $status)"
  fi
  rm -f "$log"
}

sign() {
  run_codesign --force --options runtime --timestamp=none --sign "$identity" "$@"
}

# Deepest paths first: a container is signed after what it holds.
by_depth() {
  awk -F/ '{ print NF "\t" $0 }' | sort -rn -k1,1 | cut -f2-
}

is_macho() {
  file -b "$1" | grep -q '^Mach-O'
}

# The Dart AOT runtime of the helpers maps its snapshot as executable memory,
# which the Hardened Runtime allows only with an entitlement.
helper_entitlements="$root/apps/xp_desktop/macos/Runner/Helpers.entitlements"
echo "Signing with $identity..."
main_executable="$app/Contents/MacOS/$(defaults read "$app/Contents/Info" CFBundleExecutable)"
while IFS= read -r file; do
  [[ "$file" == "$main_executable" ]] && continue
  is_macho "$file" || continue
  case "$file" in
    "$helpers/xpd/bin/xpd" | "$helpers/xp/bin/xp")
      sign --identifier "$bundle_id.$(basename "$file")" \
        --entitlements "$helper_entitlements" "$file"
      ;;
    *) sign "$file" ;;
  esac
done < <(find "$app/Contents" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) | by_depth)
while IFS= read -r nested; do
  sign "$nested"
done < <(find "$app/Contents" -depth -type d \
  \( -name '*.framework' -o -name '*.app' -o -name '*.appex' -o -name '*.xpc' \) | by_depth)
sign --entitlements "$root/apps/xp_desktop/macos/Runner/Release.entitlements" "$app"

echo "Verifying..."
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dvv "$app" 2>&1 | grep -E '^(Identifier|TeamIdentifier|Authority|CodeDirectory)'
for helper in xpd xp; do
  said="$("$helpers/$helper/bin/$helper" --version)" \
    || die "the signed $helper does not run"
  echo "Contents/Helpers/$helper/bin/$helper --version: $said"
done
echo "Built $app"

if [[ "$install" == true ]]; then
  # SIGTERM to the app's own process: an Apple Event `quit` could make
  # macOS ask for Automation access. The engine (Contents/Helpers) keeps
  # running; launchd starts the new one when it restarts.
  running="$(pgrep -f "^$installed/Contents/MacOS/" || true)"
  if [[ -n "$running" ]]; then
    echo "Quitting XPath ($running)..."
    # shellcheck disable=SC2086
    kill -TERM $running
    for _ in $(seq 1 10); do
      pgrep -f "^$installed/Contents/MacOS/" >/dev/null || break
      sleep 1
    done
    ! pgrep -f "^$installed/Contents/MacOS/" >/dev/null \
      || die "XPath is still running; quit it and run again"
  fi
  echo "Installing $installed..."
  rm -rf "$installed"
  ditto "$app" "$installed"
  echo "Installed $installed. A running engine keeps the old xpd until it"
  echo "restarts: launchctl kickstart -k gui/$(id -u)/$bundle_id.xpd"
fi
