#!/usr/bin/env bash
# The approval gate against an agent (Phase 13, D-12, D-13): a production release
# that an MCP client dispatches stops at a pending approval, and the MCP token
# cannot approve it.
#
#   mcp_gate_e2e.sh
#
# builds the `xpd` and `xp` AOT bundles (`dart build cli`) and runs
# apps/xpd/tool/release_e2e.dart --mode mcp, which
#
#   - starts `xpd serve` in a temporary data directory against a fake GitHub
#     and a fake Firebase (XPD_TEST_*; its secrets in a file, never in the
#     Keychain) and adds the fixture app (tool/e2e/build_app) as a project,
#   - creates an `app`, a `cli` and an `mcp` token, and runs
#     `xp connect --token <cli> --mcp-token <mcp>` (XP_TEST_FILE_SECRETS: the
#     tokens go to a file in a temporary config folder, never to the Keychain),
#   - adds a named Slack credential with `xp credentials add` (the webhook on
#     stdin) and assigns it with `xp credentials assign` (ADR 0013),
#   - runs `xp mcp` as a stdio subprocess and speaks MCP JSON-RPC to it:
#     initialize, tools/list (no tool that approves, denies, merges or changes
#     a gate, and `list_credentials` the only credential tool, which shows
#     the credential without its secret; the MCP token gets 403 on adding
#     one), tools/call dispatch_workflow for `prod-release`, then get_run
#     until the run waits for approval, then get_approval,
#   - checks that the MCP token gets 403 on approve, on deny and on loosening
#     the gate, and that the approval is still pending,
#   - approves with the app token and checks that the job goes on (and the MCP
#     tools see the approval as approved), then cancels the run.
#
# The `prod-release` workflow reaches its first gate before any build, so
# nothing heavy runs: no Android SDK, Xcode or store. It does need the repo's
# Dart and Flutter (3.47.6) first on PATH, git and perl; the engine links the
# Flutter SDK of this machine into its toolchain cache, as release_e2e.sh does.
# Set XPATH_E2E_FLUTTER_SDK to an SDK folder that already is the pinned version
# to skip the search for it. Works on macOS and on Linux.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "mcp_gate_e2e: $*" >&2
  exit 1
}

for tool in dart flutter git perl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on PATH"
done

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

echo "Dispatching a production release through xp mcp..."
(
  cd "$root/apps/xpd"
  dart run tool/release_e2e.dart \
    --mode mcp \
    --xpd "$work/build-xpd/bundle/bin/xpd" \
    --xp "$work/build-xp/bundle/bin/xp" \
    --fixture "$root/tool/e2e/build_app" \
    --work "$work/run" \
    --flutter-sdk "$flutter_sdk"
) || fail "the MCP gate e2e failed"

echo "OK: the production release dispatched through xp mcp stopped at a pending approval; the MCP token got 403 on approve, deny and loosening the gate, and only the app token could approve it."
