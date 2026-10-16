#!/usr/bin/env bash
# Builds the release bundles of XPath: the `xpd` and `xp` AOT bundles
# (`dart build cli`, ADR 0001) for each target, the runner bundles the engine
# hands to runners that update (D-24), and the release archives.
#
#   tool/release/bundles.sh [--targets "<os>-<arch> ..."] [--out <dir>]
#                           [--upload <tag>]
#
# Targets are `macos-arm64`, `macos-x64`, `linux-x64` and `linux-arm64`. The
# default is every target this machine can build: `dart build cli`
# cross-compiles to Linux from anywhere, but builds macOS only for the
# machine's own architecture (an Apple silicon Mac cannot build `macos-x64`).
#
# Output, in <out> (default build/release):
#
#   bundles/<target>/xpd/      bin/xpd, lib/libsqlite3.*, runners/<os>-<arch>/xp.tar.gz
#   bundles/<target>/xp/       bin/xp, lib/libsqlite3.*
#   runners/<os>-<arch>/xp.tar.gz
#                              the runner bundles, named as runners report
#                              themselves (`uname -m`: arm64, x86_64)
#   assets/                    what a GitHub Release carries:
#     xpath-<target>.tar.gz    the engine and the CLI, top folder
#                              xpath-<version>-<target>/ with VERSION, LICENSE,
#                              install.sh, xpd/ and xp/
#     xp-<target>.tar.gz       the CLI alone, top level bin/ and lib/
#     *.sha256                 the SHA-256 of each archive (`sha256sum` format)
#     install.sh               tool/release/linux/install.sh
#
# Every engine bundle carries the runner bundles of every target built in the
# same run, so build all targets together. The release workflow builds the
# Linux targets, and its dmg job the macOS ones on a public repository; else
# they come from a Mac:
#
#   tool/release/bundles.sh --upload v1.2.3
#
# builds every target this Mac can, then uploads the macOS assets to the
# existing GitHub Release v1.2.3 (`gh release upload --clobber`). The
# version must be the checkout's (`dart run tool/release_version.dart apply`).
#
# Needs the repo's Dart (3.13) first on PATH and `dart pub get` done.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/build/release"
targets=""
upload=""

die() {
  echo "bundles: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --targets) targets="${2:?--targets needs a value}"; shift 2 ;;
    --out) out="${2:?--out needs a value}"; shift 2 ;;
    --upload) upload="${2:?--upload needs a tag}"; shift 2 ;;
    -h | --help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
  esac
done

case "$(uname -s)" in
  Darwin) host_os=macos ;;
  Linux) host_os=linux ;;
  *) die "build on macOS or Linux" ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) host_arch=arm64 ;;
  x86_64 | amd64) host_arch=x64 ;;
  *) die "unsupported machine $(uname -m)" ;;
esac
host="$host_os-$host_arch"

# The archives carry plain files owned by root: no builder's user name, and no
# extended attributes (bsdtar on macOS stores com.apple.provenance, which GNU
# tar warns about).
if [[ "$host_os" == macos ]]; then
  tar_create=(tar --no-mac-metadata --no-xattrs --uid 0 --gid 0 --uname root --gname root -czf)
else
  tar_create=(tar --owner=0 --group=0 --numeric-owner -czf)
fi

if [[ -z "$targets" ]]; then
  targets="linux-x64 linux-arm64"
  [[ "$host_os" == macos ]] && targets="$host $targets"
fi

# The version is the one of the packages; both apps must agree.
version_of() { sed -n 's/^version: *//p' "$root/apps/$1/pubspec.yaml"; }
version="$(version_of xpd)"
[[ -n "$version" ]] || die "no version in apps/xpd/pubspec.yaml"
[[ "$(version_of xp)" == "$version" ]] \
  || die "apps/xp is $(version_of xp), apps/xpd is $version: release them together"
if [[ -n "$upload" ]]; then
  [[ "$upload" == "v$version" ]] || die "the tag $upload is not v$version"
  command -v gh >/dev/null 2>&1 || die "--upload needs the GitHub CLI (gh)"
fi

# `uname -m` of the target, the arch a runner reports in its hello.
runner_arch() {
  case "$1" in
    x64) echo x86_64 ;;
    *) echo "$1" ;;
  esac
}

for target in $targets; do
  case "$target" in
    macos-arm64 | macos-x64 | linux-x64 | linux-arm64) ;;
    *) die "unknown target $target (macos-arm64, macos-x64, linux-x64, linux-arm64)" ;;
  esac
  if [[ "$target" == macos-* && "$target" != "$host" ]]; then
    die "dart build cli cannot build $target on $host; build it on a Mac of that architecture"
  fi
done

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Writes <file>.sha256 next to <file>, as `sha256sum` prints it.
write_sha256() {
  echo "$(sha256_of "$1")  $(basename "$1")" >"$1.sha256"
}

# Checks that the executable of a bundle is for the target: the host's own
# bundles run, the others are checked with `file` when it is there.
check_bundle() {
  local bundle="$1" name="$2" target="$3"
  local exe="$bundle/bin/$name"
  [[ -x "$exe" ]] || die "no executable at $exe"
  compgen -G "$bundle/lib/libsqlite3.*" >/dev/null || die "no libsqlite3 in $bundle/lib"
  if [[ "$target" == "$host" ]]; then
    local said
    # `xp --version` prints the version, `xpd --version` "xpd <version> (API v1)".
    said="$("$exe" --version)"
    said="${said#xpd }"
    [[ "${said%% *}" == "$version" ]] || die "$exe --version printed $said, not $version"
  elif command -v file >/dev/null 2>&1; then
    local want
    case "$target" in
      linux-x64) want='ELF 64-bit.*x86-64' ;;
      linux-arm64) want='ELF 64-bit.*(aarch64|ARM aarch64)' ;;
      macos-x64) want='Mach-O 64-bit.*x86_64' ;;
      macos-arm64) want='Mach-O 64-bit.*arm64' ;;
    esac
    file -b "$exe" | grep -Eq "$want" || die "$exe is not a $target executable: $(file -b "$exe")"
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rm -rf "$out/bundles" "$out/runners" "$out/assets"
mkdir -p "$out/bundles" "$out/runners" "$out/assets"

for target in $targets; do
  os="${target%-*}"
  arch="${target#*-}"
  for app in xpd xp; do
    echo "Building $app for $target..."
    if ! (cd "$root/apps/$app" && dart build cli -t "bin/$app.dart" \
      --target-os "$os" --target-arch "$arch" -o "$work/$app-$target" \
      >"$work/$app-$target.log" 2>&1); then
      cat "$work/$app-$target.log" >&2
      die "dart build cli failed for $app on $target"
    fi
    mkdir -p "$out/bundles/$target"
    mv "$work/$app-$target/bundle" "$out/bundles/$target/$app"
    check_bundle "$out/bundles/$target/$app" "$app" "$target"
  done
  runner="$out/runners/$os-$(runner_arch "$arch")"
  mkdir -p "$runner"
  "${tar_create[@]}" "$runner/xp.tar.gz" -C "$out/bundles/$target/xp" bin lib
done

for target in $targets; do
  # Every engine serves the runner bundles of every target (`runners/` next
  # to its bin and lib, see runnerBundleRoots).
  cp -R "$out/runners" "$out/bundles/$target/xpd/runners"

  folder="xpath-$version-$target"
  stage="$work/stage/$folder"
  mkdir -p "$stage"
  cp -R "$out/bundles/$target/xpd" "$out/bundles/$target/xp" "$stage/"
  cp "$root/LICENSE" "$stage/LICENSE"
  cp "$root/tool/release/linux/install.sh" "$stage/install.sh"
  echo "$version" >"$stage/VERSION"
  "${tar_create[@]}" "$out/assets/xpath-$target.tar.gz" -C "$work/stage" "$folder"
  cp "$out/runners/${target%-*}-$(runner_arch "${target#*-}")/xp.tar.gz" \
    "$out/assets/xp-$target.tar.gz"
done
cp "$root/tool/release/linux/install.sh" "$out/assets/install.sh"
for asset in "$out/assets"/*.tar.gz; do
  write_sha256 "$asset"
done

echo "Built XPath $version for: $targets"
(cd "$out/assets" && ls -1)

if [[ -n "$upload" ]]; then
  mac_assets=("$out/assets"/*-macos-*)
  [[ -e "${mac_assets[0]}" ]] || die "no macOS assets to upload; build on a Mac"
  echo "Uploading the macOS assets to the release $upload..."
  gh release upload "$upload" "${mac_assets[@]}" --clobber
fi
