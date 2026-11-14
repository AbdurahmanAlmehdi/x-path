#!/usr/bin/env bash
# Runs the web dashboard's Playwright specs (apps/xp_web/e2e) against a real
# engine: builds the xpd AOT bundle (`dart build cli`) with the dashboard in
# its web/, starts it on a free port with a throwaway data directory, and
# runs the specs on Chromium, plus signin.spec.ts, runs.spec.ts and
# approvals.spec.ts on WebKit (D3a: the loopback cookie without `Secure`; the
# event and log sockets under the dashboard's CSP; deciding a gate).
#
#   tool/e2e/web_e2e.sh [<spec> ...]
#
# A <spec> narrows the run, as Playwright filters do: `signin`, `runs`,
# `approvals`.
# The specs reach the engine at $XPD_URL and make people and sign-in codes
# with $XPD_BIN and $XPD_DATA_DIR, as `xpd person` does on the engine
# machine, and git repositories of tool/e2e/build_app next to the data
# directory.
#
# The dashboard is $XPATH_WEB_DIST when set, else built from apps/xp_web
# (tool/release/web_dist.sh). Needs the repo's Dart (3.13) first on PATH,
# Node 24 with `npm ci` done in apps/xp_web, and the Playwright browsers
# (`npx playwright install chromium webkit`). Exits non-zero, after printing
# the server log, if a spec fails.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  echo "web_e2e: $*" >&2
  if [[ -f "$work/server.log" ]]; then
    echo "--- server log ---" >&2
    cat "$work/server.log" >&2
  fi
  exit 1
}

[[ -d "$root/apps/xp_web/node_modules" ]] || fail "run npm ci in apps/xp_web first"

echo "Building the xpd bundle..."
(cd "$root/apps/xpd" && dart build cli -t bin/xpd.dart -o "$work/build" >"$work/build.log" 2>&1) \
  || { cat "$work/build.log" >&2; fail "dart build cli failed"; }
xpd="$work/build/bundle/bin/xpd"
[[ -x "$xpd" ]] || fail "no executable at $xpd"
web="$("$root/tool/release/web_dist.sh")" || fail "no web dashboard"
cp -R "$web" "$work/build/bundle/web"

data="$work/data"
"$xpd" serve --port 0 --data-dir "$data" >"$work/server.log" 2>&1 &
server_pid=$!

url=""
for _ in $(seq 1 300); do
  kill -0 "$server_pid" 2>/dev/null || fail "xpd exited before it was listening"
  url="$(grep -Eo 'http://[^ ]+' "$work/server.log" | head -1 || true)"
  [[ -n "$url" ]] && break
  sleep 0.2
done
[[ -n "$url" ]] || fail "xpd did not report an address within 60 s"
grep -q 'xpd serves the dashboard in ' "$work/server.log" || fail "xpd did not find the dashboard"
echo "xpd is listening on $url"

status=0
(
  cd "$root/apps/xp_web"
  XPD_URL="$url" XPD_BIN="$xpd" XPD_DATA_DIR="$data" npx playwright test "$@"
) || status=$?
[[ "$status" == 0 ]] || fail "the Playwright specs failed"
echo "OK: the web dashboard passes its specs against a real xpd."
