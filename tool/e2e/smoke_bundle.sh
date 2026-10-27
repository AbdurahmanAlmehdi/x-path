#!/usr/bin/env bash
# Builds the xpd AOT bundle (`dart build cli`), starts it on a free port with a
# throwaway data directory and checks that it works end to end:
#
#   - GET /health answers 200 {"status":"ok"} without a token,
#   - the SQLite database (the sqlite3 build hook) opens in the bundle,
#   - GET /events without a token answers 401,
#   - `xpd token create` prints a token that the running engine accepts
#     (426: authenticated, but not a WebSocket upgrade),
#   - SIGTERM stops it cleanly (exit 0).
#
# Needs the repo's Dart (3.13) first on PATH, and curl. Works on macOS and
# Linux. Exits non-zero, after printing the server log, if anything is off.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -KILL "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

fail() {
  echo "smoke_bundle: $*" >&2
  if [[ -f "$work/server.log" ]]; then
    echo "--- server log ---" >&2
    cat "$work/server.log" >&2
  fi
  exit 1
}

echo "Building the xpd bundle..."
(cd "$root/apps/xpd" && dart build cli -t bin/xpd.dart -o "$work/build" >"$work/build.log" 2>&1) \
  || { cat "$work/build.log" >&2; fail "dart build cli failed"; }
xpd="$work/build/bundle/bin/xpd"
[[ -x "$xpd" ]] || fail "no executable at $xpd"

data="$work/data"
echo "Starting $xpd on a free port..."
"$xpd" serve --port 0 --data-dir "$data" >"$work/server.log" 2>&1 &
server_pid=$!

url=""
# xpd listens once its tool probes finish, and a tool that hangs (such as
# `swift --version` on a fresh CI runner) takes the probe's 30 s timeout.
for _ in $(seq 1 300); do
  kill -0 "$server_pid" 2>/dev/null || fail "xpd exited before it was listening"
  url="$(grep -Eo 'http://[^ ]+' "$work/server.log" | head -1 || true)"
  [[ -n "$url" ]] && break
  sleep 0.2
done
[[ -n "$url" ]] || fail "xpd did not report an address within 60 s"
echo "xpd is listening on $url"

status="$(curl -sS --max-time 5 -o "$work/health.json" -w '%{http_code}' "$url/health")"
[[ "$status" == "200" ]] || fail "GET /health answered $status"
[[ "$(cat "$work/health.json")" == '{"status":"ok"}' ]] \
  || fail "GET /health body was: $(cat "$work/health.json")"

status="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$url/events")"
[[ "$status" == "401" ]] || fail "GET /events without a token answered $status, not 401"

token="$("$xpd" token create --name smoke --kind cli --data-dir "$data" 2>/dev/null)"
[[ "$token" =~ ^xpt_[A-Za-z0-9_-]{43}$ ]] || fail "xpd token create printed an unexpected token"
[[ -s "$data/xpath.db" ]] || fail "no database at $data/xpath.db"
if grep -qaF "$token" "$data"/xpath.db*; then
  fail "the token is stored in clear text"
fi

status="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $token" "$url/events")"
[[ "$status" == "426" ]] \
  || fail "GET /events with a fresh token answered $status, not 426"

kill -TERM "$server_pid"
if wait "$server_pid"; then
  server_pid=""
else
  code=$?
  server_pid=""
  fail "xpd exited with $code after SIGTERM"
fi
grep -q 'shutting down' "$work/server.log" || fail "xpd did not log a graceful shutdown"

echo "OK: the xpd bundle answers /health, guards /events and shuts down cleanly."
