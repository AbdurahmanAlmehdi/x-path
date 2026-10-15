#!/bin/sh
# Installs XPath (the engine `xpd` and the CLI `xp`) for the current user.
# Served at https://xpath.abdurahman.ly/install:
#
#   curl -fsSL https://xpath.abdurahman.ly/install | sh
#   curl -fsSL https://xpath.abdurahman.ly/install | sh -s -- --runner
#
# Options (each also has an environment variable):
#
#   --version <v>    XPATH_VERSION     the release to install (default: the latest)
#   --prefix <dir>   XPATH_PREFIX      where to install (default: ~/.local)
#   --archive <path> XPATH_ARCHIVE     install this xpath-<os>-<arch>.tar.gz, or
#                                      this unpacked release folder, instead
#                                      of downloading one
#   --runner         XPATH_RUNNER=1    a runner machine: no engine service; pair
#                                      the runner afterwards
#   --no-service     XPATH_NO_SERVICE=1  install the files only
#
# It puts the bundles in <prefix>/lib/xpath/{xpd,xp} and links
# <prefix>/bin/xpd and <prefix>/bin/xp to them. On Linux with a systemd user
# session it then runs `xpd install-service`: the user unit
# ~/.config/systemd/user/xpd.service (tool/release/linux/xpd.service without
# the master key credential), enabled and started, and restarted when it was
# there already. A runner gets xp-runner.service from `xp runner
# install-service` once paired. Running it again updates in place; run from
# an unpacked release folder (xpath-<version>-<os>-<arch>/) it installs that.
#
# Downloads come from XPATH_RELEASES_URL (default: the GitHub Releases of
# AbdurahmanAlmehdi/x-path), checked against the .sha256 published with them.
set -eu

repo_releases="https://github.com/AbdurahmanAlmehdi/x-path/releases"
releases="${XPATH_RELEASES_URL:-$repo_releases}"
version="${XPATH_VERSION:-}"
prefix="${XPATH_PREFIX:-${HOME:?HOME is not set}/.local}"
archive="${XPATH_ARCHIVE:-}"
runner="${XPATH_RUNNER:-0}"
no_service="${XPATH_NO_SERVICE:-0}"

say() { printf '%s\n' "$*"; }
die() {
  printf 'xpath install: %s\n' "$*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || die "--version needs a value"; version="$2"; shift 2 ;;
    --prefix) [ $# -ge 2 ] || die "--prefix needs a value"; prefix="$2"; shift 2 ;;
    --archive) [ $# -ge 2 ] || die "--archive needs a value"; archive="$2"; shift 2 ;;
    --runner) runner=1; shift ;;
    --no-service) no_service=1; shift ;;
    -h | --help)
      if [ -f "$0" ]; then sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; else say "The options are at the top of https://xpath.abdurahman.ly/install."; fi
      exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) die "XPath runs on Linux and macOS, not $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) die "there is no XPath build for $(uname -m)" ;;
esac
target="$os-$arch"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    die "need sha256sum or shasum to check the download"
  fi
}

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto '=https,file' -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "need curl or wget to download XPath"
  fi
}

# Where the release folder comes from: this script's own folder, a folder or
# an archive given, or a download.
here=""
case "$0" in
  */install.sh) here="$(cd "$(dirname "$0")" && pwd)" ;;
esac
if [ -z "$archive" ] && [ -n "$here" ] && [ -f "$here/VERSION" ] && [ -x "$here/xpd/bin/xpd" ]; then
  archive="$here"
fi

if [ -z "$archive" ]; then
  name="xpath-$target.tar.gz"
  if [ -n "$version" ]; then
    url="$releases/download/v${version#v}/$name"
  else
    url="$releases/latest/download/$name"
  fi
  say "Downloading $url"
  fetch "$url" "$work/$name" || die "cannot download $url"
  fetch "$url.sha256" "$work/$name.sha256" || die "cannot download $url.sha256"
  want="$(cut -d' ' -f1 <"$work/$name.sha256")"
  [ "$(sha256_of "$work/$name")" = "$want" ] \
    || die "the SHA-256 of $name does not match $name.sha256; not installing"
  archive="$work/$name"
fi

if [ -d "$archive" ]; then
  source_dir="$archive"
elif [ -f "$archive" ]; then
  mkdir "$work/unpacked"
  tar -xzf "$archive" -C "$work/unpacked" || die "cannot unpack $archive"
  source_dir="$(find "$work/unpacked" -mindepth 1 -maxdepth 1 -type d -name 'xpath-*' | head -n 1)"
  [ -n "$source_dir" ] || die "$archive is not an XPath release archive"
else
  die "no such archive: $archive"
fi
[ -f "$source_dir/VERSION" ] || die "$source_dir has no VERSION: not an XPath release"
release="$(cat "$source_dir/VERSION")"
if [ -n "$version" ] && [ "${version#v}" != "$release" ]; then
  die "asked for $version, but the archive is $release"
fi

lib="$prefix/lib/xpath"
bin="$prefix/bin"
mkdir -p "$lib" "$bin"

# Copy beside the installed bundles, check that they run on this machine (the
# right architecture and C library), then swap them in.
stage="$lib/.install-$$"
rm -rf "$lib"/.install-*
mkdir -p "$stage"
cp -R "$source_dir/xpd" "$source_dir/xp" "$stage/" || die "cannot copy into $lib"
for app in xpd xp; do
  said="$("$stage/$app/bin/$app" --version 2>&1)" \
    || { rm -rf "$stage"; die "$app $release does not start on this machine: $said"; }
  # `xp --version` prints the version, `xpd --version` "xpd <version> (API v1)".
  said="${said#xpd }"
  [ "${said%% *}" = "$release" ] \
    || { rm -rf "$stage"; die "$app printed version $said, the archive says $release"; }
done
for app in xpd xp; do
  rm -rf "$lib/$app.old"
  if [ -e "$lib/$app" ]; then mv "$lib/$app" "$lib/$app.old"; fi
  mv "$stage/$app" "$lib/$app"
  rm -rf "$lib/$app.old"
  ln -sfn "../lib/xpath/$app/bin/$app" "$bin/$app"
done
rm -rf "$stage"
say "Installed XPath $release in $lib (xpd and xp linked in $bin)."

case ":${PATH:-}:" in
  *":$bin:"*) ;;
  *) say "Add $bin to your PATH, for example: echo 'export PATH=\"$bin:\$PATH\"' >> ~/.profile" ;;
esac

has_user_systemd() {
  [ "$os" = linux ] && command -v systemctl >/dev/null 2>&1 \
    && systemctl --user show-environment >/dev/null 2>&1
}

if [ "$runner" = 1 ]; then
  say ""
  say "Next, pair this runner (the token comes from \`xp runners pair <name>\` on the engine):"
  say "  $bin/xp runner pair --engine <engine url> --token <pairing token>"
  say "  $bin/xp runner install-service"
elif [ "$no_service" = 1 ]; then
  say "Not installing a service (--no-service). Start the engine with: $bin/xpd serve"
elif has_user_systemd; then
  unit="$HOME/.config/systemd/user/xpd.service"
  existed=0
  [ -f "$unit" ] && existed=1
  "$lib/xpd/bin/xpd" install-service --executable "$lib/xpd/bin/xpd"
  if [ "$existed" = 1 ]; then
    systemctl --user restart xpd.service
    say "Restarted the xpd service on $release."
  fi
elif [ "$os" = macos ]; then
  say "On a Mac the XPath app runs the engine. Without the app: $bin/xpd install-service"
else
  say "No systemd user session here: start the engine with $bin/xpd serve,"
  say "or as root: $bin/xpd install-service --system --run-as <user>"
fi
