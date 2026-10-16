#!/usr/bin/env bash
# Builds XPath.app for this Mac, with the engine (`xpd`) and the CLI (`xp`)
# inside: signed for a local install, or with Developer ID, in a DMG and
# notarized for a download.
#
#   tool/release/build_mac.sh [--reuse-bundles] [--developer-id] [--dmg]
#                             [--notarize] [--upload v<version>] [--install]
#
# Steps:
#   1. tool/release/bundles.sh builds the `xpd` and `xp` bundles for this
#      Mac (and the Linux runner bundles the engine hands to runners),
#      unless --reuse-bundles takes the ones already in build/release.
#   2. `flutter build macos --release` builds apps/xp_desktop. Its version
#      (CFBundleShortVersionString) must be the version of apps/xpd.
#   3. The bundles go into XPath.app/Contents/Helpers/xpd/{bin,lib} and
#      Contents/Helpers/xp/{bin,lib}: the LaunchAgent plist runs
#      Contents/Helpers/xpd/bin/xpd (BundleProgram), and the app links
#      Contents/Helpers/xp/bin/xp into PATH. The runner archives go into
#      Contents/Resources/runners (Helpers may hold only code).
#   4. Every Mach-O inside is signed, deepest first, then the frameworks,
#      then the app (Release entitlements), all with the Hardened Runtime.
#      The helpers get Helpers.entitlements: the Dart AOT runtime needs
#      allow-unsigned-executable-memory under the Hardened Runtime.
#   5. `codesign --verify --deep --strict` checks the app, and the signed
#      helpers must print their --version.
#
# The result is dist/XPath.app.
#
#   --developer-id  signs with a "Developer ID Application: ... (<team>)"
#                   identity, with a secure timestamp (needs the network),
#                   instead of the Apple Development one without. It is
#                   found in the keychain by team, or named by
#                   $XPATH_SIGN_IDENTITY; nothing else is accepted.
#   --dmg           builds dist/XPath-<version>.dmg (the app and a link to
#                   /Applications), signs it with the same identity and
#                   checks that it mounts and holds the signed app.
#   --notarize      (needs --developer-id) submits the app, staples it,
#                   then the DMG (with --dmg), staples it too, and runs
#                   `spctl -a -vv` (`-t install` for the DMG). Credentials:
#                   $XPATH_NOTARY_PROFILE (a `notarytool store-credentials`
#                   keychain profile), or an App Store Connect API key:
#                   $XPATH_NOTARY_KEY (the .p8 file), $XPATH_NOTARY_KEY_ID
#                   and $XPATH_NOTARY_ISSUER.
#   --upload <tag>  (needs --dmg and --notarize) attaches the DMG to the
#                   existing GitHub Release <tag>, which must be
#                   v<version> (`gh release upload --clobber`).
#   --install       quits a running XPath, replaces /Applications/XPath.app
#                   with dist/XPath.app, and makes LaunchServices forget the
#                   build-folder copies (apps/xp_desktop/build/macos/Build/
#                   Products/*/XPath.app, dist/XPath.app): they share the
#                   bundle id, so macOS could open a Debug build instead,
#                   whose LaunchAgent points at a bundle without xpd. It does
#                   nothing else: it does not open the app, register the
#                   engine's LaunchAgent or link `xp`.
#
# Signing identity without --developer-id: $XPATH_SIGN_IDENTITY, by default
# the owner's "Apple Development: Abdurahman Ibrahem (L7UMZN6DL6)", for this
# Mac only (Gatekeeper rejects it elsewhere). The team is $XPATH_TEAM_ID,
# by default AFBD5TBR5U. A codesign that waits more than 60 s (a Keychain
# dialog) is stopped.
#
# Needs the repo's Flutter (.fvm/flutter_sdk/bin) first on PATH and
# `dart pub get` done.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
team="${XPATH_TEAM_ID:-AFBD5TBR5U}"
development_identity="3B9E9C2FB4D94EFC7AC367C68CF1FC077EBB799F"
bundle_id="ly.abdurahman.xpath"
dist="$root/dist"
app="$dist/XPath.app"
installed="/Applications/XPath.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
sign_timeout=60
reuse=false
developer_id=false
make_dmg=false
notarize=false
upload=""
install=false

die() {
  echo "build_mac: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reuse-bundles) reuse=true; shift ;;
    --developer-id) developer_id=true; shift ;;
    --dmg) make_dmg=true; shift ;;
    --notarize) notarize=true; shift ;;
    --upload) upload="${2:?--upload needs a tag}"; shift 2 ;;
    --install) install=true; shift ;;
    -h | --help) sed -n '2,63p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done

if [[ "$notarize" == true && "$developer_id" == false ]]; then
  die "--notarize needs --developer-id: Apple notarizes only Developer ID signed code"
fi
if [[ -n "$upload" && ( "$make_dmg" == false || "$notarize" == false ) ]]; then
  die "--upload needs --dmg and --notarize: only a notarized DMG is published"
fi

[[ "$(uname -s)" == Darwin ]] || die "build XPath.app on a Mac"
case "$(uname -m)" in
  arm64) host=macos-arm64 ;;
  x86_64) host=macos-x64 ;;
  *) die "unsupported machine $(uname -m)" ;;
esac
command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH"

# The release is the version of apps/xpd; the app (CFBundleShortVersionString)
# and xp must carry the same (tool/release_version.dart apply writes all).
version_of() { sed -n 's/^version: *//p' "$root/apps/$1/pubspec.yaml"; }
version="$(version_of xpd)"
[[ -n "$version" ]] || die "no version in apps/xpd/pubspec.yaml"
app_version="$(version_of xp_desktop)"
[[ "${app_version%%+*}" == "$version" ]] \
  || die "apps/xp_desktop is $app_version, apps/xpd is $version: write both with tool/release_version.dart apply"
if [[ -n "$upload" ]]; then
  [[ "$upload" == "v$version" ]] || die "the tag $upload is not v$version"
  command -v gh >/dev/null 2>&1 || die "--upload needs the GitHub CLI (gh)"
fi

# The SHA-1 of the one "Developer ID Application: ... (<team>)" identity in
# the keychain, or of the one $XPATH_SIGN_IDENTITY names (by SHA-1 or full
# name). Apple Distribution and Apple Development identities are refused:
# outside the App Store, Gatekeeper accepts only Developer ID.
developer_id_identity() {
  local identities matches line name
  identities="$(security find-identity -v -p codesigning)"
  if [[ -n "${XPATH_SIGN_IDENTITY:-}" ]]; then
    matches="$(awk -v want="$XPATH_SIGN_IDENTITY" '{
      name = $0; sub(/^[^"]*"/, "", name); sub(/"$/, "", name)
      if ($2 == want || name == want) print
    }' <<<"$identities")"
    [[ -n "$matches" ]] \
      || die "XPATH_SIGN_IDENTITY ($XPATH_SIGN_IDENTITY) is not a valid signing identity in the keychain"
  else
    matches="$(grep -E "\"Developer ID Application: .* \($team\)\"\$" <<<"$identities" || true)"
    if [[ -z "$matches" ]]; then
      cat >&2 <<MESSAGE
build_mac: no "Developer ID Application: ... ($team)" identity in the keychain.
Outside the Mac App Store, Gatekeeper accepts only Developer ID; an Apple
Distribution or Apple Development certificate cannot sign the download.
Create one (only the Account Holder of the team can):
  Xcode > Settings > Accounts > the team > Manage Certificates... > + >
  Developer ID Application
or at https://developer.apple.com/account/resources/certificates/add with a
certificate signing request from Keychain Access, then double-click the
downloaded certificate. Run again, or set XPATH_SIGN_IDENTITY to its SHA-1
(security find-identity -v -p codesigning).
MESSAGE
      exit 1
    fi
  fi
  if (($(wc -l <<<"$matches") > 1)); then
    echo "$matches" >&2
    die "more than one identity matches; set XPATH_SIGN_IDENTITY to the SHA-1 of one"
  fi
  line="$matches"
  name="$(sed -E 's/^[^"]*"(.*)"$/\1/' <<<"$line")"
  [[ "$name" == "Developer ID Application: "*" ($team)" ]] \
    || die "$name is not a Developer ID Application identity of team $team"
  awk '{ print $2 }' <<<"$line"
}

if [[ "$developer_id" == true ]]; then
  identity="$(developer_id_identity)"
  timestamp=(--timestamp)
else
  identity="${XPATH_SIGN_IDENTITY:-$development_identity}"
  timestamp=(--timestamp=none)
fi

# notarytool's credentials: a keychain profile, or an App Store Connect API
# key. Checked before the build so that a missing one fails fast.
notary_auth=()
if [[ "$notarize" == true ]]; then
  if [[ -n "${XPATH_NOTARY_PROFILE:-}" ]]; then
    notary_auth=(--keychain-profile "$XPATH_NOTARY_PROFILE")
  elif [[ -n "${XPATH_NOTARY_KEY:-}" && -n "${XPATH_NOTARY_KEY_ID:-}" && -n "${XPATH_NOTARY_ISSUER:-}" ]]; then
    [[ -r "$XPATH_NOTARY_KEY" ]] || die "XPATH_NOTARY_KEY ($XPATH_NOTARY_KEY) is not a readable file"
    notary_auth=(--key "$XPATH_NOTARY_KEY" --key-id "$XPATH_NOTARY_KEY_ID" --issuer "$XPATH_NOTARY_ISSUER")
  else
    die "--notarize needs XPATH_NOTARY_PROFILE, or XPATH_NOTARY_KEY, XPATH_NOTARY_KEY_ID and XPATH_NOTARY_ISSUER"
  fi
fi

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
built_version="$(defaults read "$built/Contents/Info" CFBundleShortVersionString)"
[[ "$built_version" == "$version" ]] \
  || die "the app's CFBundleShortVersionString is $built_version, not $version"

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
  run_codesign --force --options runtime "${timestamp[@]}" --sign "$identity" "$@"
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
identity_name="$(security find-identity -v -p codesigning \
  | grep -F -- "$identity" | head -1 | sed -E 's/^[^"]*"(.*)"$/\1/' || true)"
echo "Signing with $identity ${identity_name:+($identity_name) }${timestamp[*]}..."
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
# The macOS runner archives the engine hands to Mac runners hold code too, and
# the notary service looks inside archives: sign what they hold and pack them
# again (same layout and ownership as bundles.sh), before the app seals them.
while IFS= read -r archive; do
  unpacked="$(mktemp -d)"
  tar -xzf "$archive" -C "$unpacked"
  while IFS= read -r file; do
    is_macho "$file" || continue
    if [[ "$file" == "$unpacked/bin/xp" ]]; then
      sign --identifier "$bundle_id.xp" --entitlements "$helper_entitlements" "$file"
    else
      sign "$file"
    fi
  done < <(find "$unpacked" -type f | by_depth)
  tar --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname root \
    -czf "$archive" -C "$unpacked" bin lib
  rm -rf "$unpacked"
done < <(find "$app/Contents/Resources/runners" -path '*/macos-*/xp.tar.gz' 2>/dev/null)
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
  # `xp --version` prints the version, `xpd --version` "xpd <version> (API v1)".
  said="${said#xpd }"
  [[ "${said%% *}" == "$version" ]] \
    || die "the bundled $helper is ${said%% *}, not $version; run without --reuse-bundles"
done
echo "Built $app ($version)"

# Submits <file> to Apple's notary service and waits for the verdict; on
# anything but Accepted it prints the log and stops.
notarize_file() {
  local file="$1" result status id
  result="$(mktemp)"
  echo "Notarizing $(basename "$file") (xcrun notarytool submit --wait)..."
  xcrun notarytool submit "$file" "${notary_auth[@]}" --wait --output-format json >"$result" \
    || true
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
  if [[ "$status" != Accepted ]]; then
    cat "$result" >&2
    if [[ -n "$id" ]]; then
      xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true
    fi
    rm -f "$result"
    die "notarization of $(basename "$file") ended ${status:-without a verdict}"
  fi
  rm -f "$result"
  echo "Notarized $(basename "$file") (submission $id)."
}

staple() {
  xcrun stapler staple "$1"
  xcrun stapler validate "$1"
}

if [[ "$notarize" == true ]]; then
  # The app first, so that the copy in the DMG carries its own ticket.
  zip="$(mktemp -d)/XPath.zip"
  ditto -c -k --keepParent "$app" "$zip"
  notarize_file "$zip"
  rm -rf "$(dirname "$zip")"
  staple "$app"
fi

dmg=""
if [[ "$make_dmg" == true ]]; then
  dmg="$dist/XPath-$version.dmg"
  echo "Building $dmg..."
  stage="$(mktemp -d)"
  ditto "$app" "$stage/XPath.app"
  ln -s /Applications "$stage/Applications"
  rm -f "$dmg"
  # hdiutil fails now and then with "Resource busy" on a busy machine.
  made=false
  for _ in 1 2 3; do
    if hdiutil create -quiet -volname "XPath $version" -srcfolder "$stage" \
      -fs HFS+ -format UDZO -ov "$dmg"; then
      made=true
      break
    fi
    sleep 5
  done
  rm -rf "$stage"
  [[ "$made" == true ]] || die "hdiutil could not create $dmg"
  run_codesign --force "${timestamp[@]}" --sign "$identity" "$dmg"
  codesign --verify --strict --verbose=2 "$dmg"

  # It must mount and hold the signed app and the /Applications link.
  mount="$(mktemp -d)"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
  check_status=0
  codesign --verify --deep --strict "$mount/XPath.app" || check_status=$?
  [[ "$(readlink "$mount/Applications")" == /Applications ]] || check_status=1
  hdiutil detach -quiet "$mount" || hdiutil detach -quiet -force "$mount"
  rmdir "$mount" 2>/dev/null || true
  ((check_status == 0)) || die "$dmg does not hold a signed XPath.app and the /Applications link"
  echo "Built $dmg"
  if [[ "$developer_id" == false ]]; then
    echo "$(basename "$dmg") is signed with Apple Development: for this Mac only, not for"
    echo "distribution (Gatekeeper rejects it elsewhere). A download needs --developer-id --notarize."
  fi
fi

if [[ "$notarize" == true ]]; then
  if [[ -n "$dmg" ]]; then
    notarize_file "$dmg"
    staple "$dmg"
    spctl -a -vv -t install "$dmg"
  else
    spctl -a -vv -t exec "$app"
  fi
elif [[ "$developer_id" == true ]]; then
  echo "Not notarized: Gatekeeper rejects it on another Mac until it is (--notarize)."
fi

if [[ -n "$upload" ]]; then
  echo "Uploading $(basename "$dmg") to the release $upload..."
  gh release upload "$upload" "$dmg" --clobber
fi

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
  # The build-folder copies share $bundle_id: unregister them so that
  # LaunchServices opens (and registers the LaunchAgent of) the installed one.
  for copy in "$root"/apps/xp_desktop/build/macos/Build/Products/*/XPath.app "$app"; do
    if [[ -d "$copy" ]]; then
      "$lsregister" -u "$copy" >/dev/null 2>&1 || true
    fi
  done
  "$lsregister" -f "$installed" >/dev/null 2>&1 \
    || echo "build_mac: lsregister could not register $installed" >&2
  echo "LaunchServices now opens $bundle_id from $installed only (build copies unregistered)."
  echo "Installed $installed. A running engine keeps the old xpd until it"
  echo "restarts: launchctl kickstart -k gui/$(id -u)/$bundle_id.xpd"
fi
