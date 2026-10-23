#!/usr/bin/env bash
# Tests tool/release/linux/install.sh against the release archive of this
# machine that tool/release/bundles.sh made, with no network:
#
#   tool/release/linux/install_test.sh [<assets dir>]   (default build/release/assets)
#
# Every run uses a throwaway HOME and prefix and a clean environment. It checks
# an install from the archive, an update in place from the unpacked release
# folder, a download (file:// URLs standing in for GitHub Releases) with and
# without a version, a refused download whose SHA-256 does not match, a
# refused version mismatch and the runner mode. On Linux it also checks the
# service step against a fake `systemctl` and `loginctl` on PATH: the user
# unit `xpd install-service` writes, `enable --now`, and a restart on update,
# and `--with-android` against a fake `apt-get`, `sudo`, `dpkg-query` and
# `sdkmanager` (in a local command-line tools zip): the packages, the SDK, a
# wrong SHA-256, a system that is not Debian, and a run that finds everything
# installed. No test talks to the real service manager or package manager.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
assets="$(cd "${1:-$root/build/release/assets}" && pwd)"
installer="$root/tool/release/linux/install.sh"

case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux) os=linux ;;
  *) echo "install_test: macOS or Linux only" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) arch=arm64 ;;
  x86_64 | amd64) arch=x64 ;;
esac
target="$os-$arch"
archive="$assets/xpath-$target.tar.gz"
[[ -f "$archive" ]] || { echo "install_test: no $archive; run tool/release/bundles.sh first" >&2; exit 1; }
# XPATH_VERSION: the release version, when this checkout's pubspecs still say
# the development one (a release job that did not write the version in).
version="${XPATH_VERSION:-$(sed -n 's/^version: *//p' "$root/apps/xpd/pubspec.yaml")}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "install_test: $*" >&2
  [[ -f "$work/out.log" ]] && { echo "--- output ---" >&2; cat "$work/out.log" >&2; }
  exit 1
}

home="$work/home"
prefix="$work/prefix"
fakes="$work/fakes"
mkdir -p "$home" "$fakes"
base_path="/usr/bin:/bin:/usr/sbin:/sbin"

# Runs install.sh (or the given script) in a clean environment; output goes
# to out.log. Extra environment comes before `--`.
run_install() {
  local script="$installer" env_args=()
  while [[ $# -gt 0 && "$1" != -- ]]; do env_args+=("$1"); shift; done
  shift
  if [[ "${1:-}" == --script ]]; then script="$2"; shift 2; fi
  env -i HOME="$home" USER=tester PATH="$base_path" ${env_args[@]+"${env_args[@]}"} \
    sh "$script" "$@" >"$work/out.log" 2>&1
}

expect_installed() {
  local said
  [[ -L "$prefix/bin/xpd" && -L "$prefix/bin/xp" ]] || fail "no links in $prefix/bin"
  [[ "$(readlink "$prefix/bin/xpd")" == ../lib/xpath/xpd/bin/xpd ]] || fail "xpd link is $(readlink "$prefix/bin/xpd")"
  said="$("$prefix/bin/xp" --version)"
  [[ "$said" == "$version" ]] || fail "xp --version printed $said"
  said="$("$prefix/bin/xpd" --version)"
  [[ "$said" == "xpd $version"* ]] || fail "xpd --version printed $said"
  [[ -f "$prefix/lib/xpath/xpd/runners/$os-$( [[ $arch == x64 ]] && echo x86_64 || echo "$arch")/xp.tar.gz" ]] \
    || fail "the engine bundle has no runner bundle for this machine"
  compgen -G "$prefix/lib/xpath/.install-*" >/dev/null && fail "a staging folder was left behind"
  compgen -G "$prefix/lib/xpath/*.old" >/dev/null && fail "an old bundle was left behind"
  return 0
}

echo "1. Install from the archive, files only..."
run_install -- --archive "$archive" --prefix "$prefix" --no-service || fail "install failed"
expect_installed
grep -q "Installed XPath $version" "$work/out.log" || fail "no install message"
grep -q "Add $prefix/bin to your PATH" "$work/out.log" || fail "no PATH hint"
# The linked xpd finds its SQLite library: a token needs the database.
token="$("$prefix/bin/xpd" token create --name test --kind cli --data-dir "$work/data" 2>/dev/null)"
[[ "$token" == xpt_* ]] || fail "the linked xpd did not create a token"

echo "2. Update in place from the unpacked release folder..."
mkdir "$work/unpacked"
tar -xzf "$archive" -C "$work/unpacked"
echo stale >"$prefix/lib/xpath/xpd/stale"
run_install -- --script "$work/unpacked/xpath-$version-$target/install.sh" \
  --prefix "$prefix" --no-service || fail "update from the release folder failed"
expect_installed
[[ ! -e "$prefix/lib/xpath/xpd/stale" ]] || fail "the update kept a file of the old bundle"

echo "3. Download a version and the latest (file:// releases)..."
releases="$work/releases"
mkdir -p "$releases/download/v$version" "$releases/latest/download"
for dir in "$releases/download/v$version" "$releases/latest/download"; do
  cp "$archive" "$archive.sha256" "$dir/"
done
rm -rf "$prefix"
run_install XPATH_RELEASES_URL="file://$releases" -- --version "$version" --prefix "$prefix" --no-service \
  || fail "install of version $version by download failed"
expect_installed
grep -q "download/v$version/xpath-$target.tar.gz" "$work/out.log" || fail "did not download the version asked for"
rm -rf "$prefix"
run_install XPATH_RELEASES_URL="file://$releases" XPATH_PREFIX="$prefix" XPATH_NO_SERVICE=1 -- \
  || fail "install of the latest by download failed"
expect_installed
grep -q "latest/download/xpath-$target.tar.gz" "$work/out.log" || fail "did not download the latest"

echo "4. Refuse a download whose SHA-256 does not match..."
echo "0000000000000000000000000000000000000000000000000000000000000000  xpath-$target.tar.gz" \
  >"$releases/latest/download/xpath-$target.tar.gz.sha256"
echo stays >"$prefix/lib/xpath/xp/marker"
if run_install XPATH_RELEASES_URL="file://$releases" -- --prefix "$prefix" --no-service; then
  fail "installed an archive whose SHA-256 does not match"
fi
grep -q "does not match" "$work/out.log" || fail "no SHA-256 message"
[[ -f "$prefix/lib/xpath/xp/marker" ]] || fail "a refused download changed the installation"

echo "5. Refuse an archive of another version..."
if run_install -- --archive "$archive" --version 99.0.0 --prefix "$prefix" --no-service; then
  fail "installed an archive of another version"
fi
grep -q "asked for 99.0.0" "$work/out.log" || fail "no version message"

echo "6. Runner mode..."
run_install -- --archive "$archive" --prefix "$prefix" --runner || fail "runner install failed"
expect_installed
grep -q "xp runner doctor" "$work/out.log" || fail "no doctor step"
grep -q "xp runner pair --engine" "$work/out.log" || fail "no pairing hint"
grep -q "xp runner install-service" "$work/out.log" || fail "no runner service hint"

if [[ "$os" != linux ]]; then
  echo "6b. --with-android is for Linux..."
  if run_install -- --archive "$archive" --prefix "$prefix" --runner --with-android; then
    fail "--with-android ran on $os"
  fi
  grep -q "is for Debian and Ubuntu" "$work/out.log" || fail "no Debian message"
fi

if [[ "$os" == linux ]]; then
  echo "7. Service step (fake systemctl and loginctl)..."
  cat >"$fakes/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >>"$work/calls.log"
exit 0
EOF
  cat >"$fakes/loginctl" <<'EOF'
#!/bin/sh
echo "Linger=no"
EOF
  chmod +x "$fakes/systemctl" "$fakes/loginctl"
  base_path="$fakes:$base_path"
  run_install -- --archive "$archive" --prefix "$prefix" || fail "install with the service failed"
  unit="$home/.config/systemd/user/xpd.service"
  [[ -f "$unit" ]] || fail "no unit at $unit"
  grep -qF "ExecStart=$prefix/lib/xpath/xpd/bin/xpd serve --data-dir $home/.local/share/xpath" "$unit" \
    || fail "unexpected ExecStart in $unit: $(grep ExecStart "$unit")"
  grep -q "systemctl --user enable --now xpd.service" "$work/calls.log" || fail "the unit was not enabled"
  grep -q "enable-linger tester" "$work/out.log" || fail "no linger hint"
  grep -q "restart" "$work/calls.log" && fail "restarted a service that was not there before"
  run_install -- --archive "$archive" --prefix "$prefix" || fail "update with the service failed"
  grep -q "systemctl --user restart xpd.service" "$work/calls.log" || fail "the update did not restart the service"

  echo "8. --with-android (fake apt-get, sudo, dpkg-query and sdkmanager)..."
  android="$work/android"
  mkdir -p "$android/fakes" "$android/zip/cmdline-tools/bin"
  # dpkg-query says a package is installed once the fake apt-get installed it.
  cat >"$android/fakes/dpkg-query" <<FAKE
#!/bin/sh
for last; do :; done
grep -qx "\$last" "$android/installed" 2>/dev/null && echo "install ok installed"
exit 0
FAKE
  cat >"$android/fakes/apt-get" <<FAKE
#!/bin/sh
echo "apt-get \$*" >>"$android/calls.log"
[ "\$1" = install ] || exit 0
for word; do case "\$word" in -*|install) ;; *) echo "\$word" >>"$android/installed" ;; esac; done
FAKE
  cat >"$android/fakes/sudo" <<FAKE
#!/bin/sh
echo "sudo \$*" >>"$android/calls.log"
exec "\$@"
FAKE
  cat >"$android/zip/cmdline-tools/bin/sdkmanager" <<FAKE
#!/bin/sh
echo "sdkmanager \$*" >>"$android/calls.log"
root=""
for word; do case "\$word" in --sdk_root=*) root="\${word#--sdk_root=}" ;; esac; done
for word; do
  case "\$word" in
    # One answer, as the real one reads one per licence: \`yes\` never ends.
    --licenses) read -r _ || :; mkdir -p "\$root/licenses" ;;
    --*) ;;
    *) mkdir -p "\$root/\$(printf '%s' "\$word" | tr ';' /)" ;;
  esac
done
FAKE
  chmod +x "$android/fakes/"* "$android/zip/cmdline-tools/bin/sdkmanager"
  (cd "$android/zip" && zip -qr "$android/tools.zip" cmdline-tools)
  tools_sha="$( (sha256sum "$android/tools.zip" 2>/dev/null || shasum -a 256 "$android/tools.zip") | cut -d' ' -f1)"
  printf 'ID=ubuntu\nID_LIKE=debian\n' >"$android/ubuntu"
  printf 'ID=fedora\n' >"$android/fedora"
  sdk="$work/sdk"
  base_path="$android/fakes:$base_path"
  android_env=(
    XPATH_ANDROID_TOOLS_URL="file://$android/tools.zip"
    XPATH_ANDROID_TOOLS_SHA256="$tools_sha"
    XPATH_OS_RELEASE="$android/ubuntu"
  )

  if run_install "${android_env[@]}" XPATH_OS_RELEASE="$android/fedora" -- --archive "$archive" \
    --prefix "$prefix" --runner --with-android --android-sdk "$sdk"; then
    fail "--with-android ran on Fedora"
  fi
  grep -q "on Debian or Ubuntu only, not 'fedora'" "$work/out.log" || fail "no message for a system that is not Debian"

  if run_install "${android_env[@]}" XPATH_ANDROID_TOOLS_SHA256=0000 -- --archive "$archive" --prefix "$prefix" \
    --runner --with-android --android-sdk "$sdk"; then
    fail "installed command-line tools whose SHA-256 does not match"
  fi
  grep -q "SHA-256 of the Android command-line tools does not match" "$work/out.log" || fail "no SHA-256 message"
  [[ ! -e "$sdk/cmdline-tools/latest" ]] || fail "a refused download left command-line tools behind"
  rm -f "$android/installed" "$android/calls.log"

  run_install "${android_env[@]}" -- --archive "$archive" --prefix "$prefix" --runner --with-android \
    --android-sdk "$sdk" || fail "--with-android failed"
  grep -q "sudo apt-get install -y -q --no-install-recommends openjdk-17-jdk-headless git openssh-client curl unzip xz-utils zip perl" \
    "$android/calls.log" || fail "the packages were not installed through sudo: $(cat "$android/calls.log")"
  [[ -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ]] || fail "no sdkmanager in $sdk"
  grep -q -- "--licenses" "$android/calls.log" || fail "the licences were not accepted"
  for dir in platform-tools platforms/android-36 build-tools/36.0.0; do
    [[ -d "$sdk/$dir" ]] || fail "no $dir in $sdk"
  done
  grep -q "export ANDROID_HOME=$sdk" "$work/out.log" || fail "no ANDROID_HOME line for an SDK Flutter does not look in"
  grep -q "xp runner doctor" "$work/out.log" || fail "no doctor step after --with-android"

  echo "9. --with-android again skips what is there..."
  rm -f "$android/calls.log"
  run_install "${android_env[@]}" XPATH_ANDROID_TOOLS_URL="file://$android/missing.zip" -- --archive "$archive" \
    --prefix "$prefix" --runner --with-android --android-sdk "$sdk" || fail "--with-android again failed"
  grep -q "apt-get" "$android/calls.log" && fail "installed packages that are installed"
  grep -q "Downloading the Android command-line tools" "$work/out.log" && fail "downloaded the command-line tools again"
  grep -q "sdkmanager --sdk_root=$sdk platform" "$android/calls.log" && fail "installed SDK packages again"
else
  echo "7. Service step on macOS: hint only..."
  run_install -- --archive "$archive" --prefix "$prefix" || fail "install failed"
  grep -q "the XPath app runs the engine" "$work/out.log" || fail "no macOS hint"
  [[ ! -e "$home/Library/LaunchAgents" ]] || fail "install.sh touched LaunchAgents"
fi

echo "OK: install.sh installs, updates, verifies downloads, sets up the service and, with --with-android, the Android SDK."
