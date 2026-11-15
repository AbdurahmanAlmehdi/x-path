#!/usr/bin/env bash
# Builds the xpd AOT bundle (`dart build cli`), starts it on a free port with a
# throwaway data directory and checks that it works end to end:
#
#   - GET /api/v1/health answers 200 {"status":"ok"} without a token, and
#     so does its deprecated root alias /health,
#   - the SQLite database (the sqlite3 build hook) opens in the bundle,
#   - GET /api/v1/events without a token answers 401, and /events without
#     Authorization is not the API (404),
#   - `xpd token create` prints a token that the running engine accepts
#     (426: authenticated, but not a WebSocket upgrade),
#   - GET /projects with the token gives the body of /api/v1/projects, and
#     only the root alias says `Deprecation: true` (ADR 0018),
#   - the web dashboard in the bundle's web/ is served: GET / and a deep link
#     are index.html with the Content-Security-Policy, an asset under
#     /assets/ is immutable, and a path under /api is never the dashboard,
#   - SIGTERM stops it cleanly (exit 0).
#
# The dashboard is $XPATH_WEB_DIST when set, else built from apps/xp_web
# (tool/release/web_dist.sh, which needs Node 24 and npm).
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
web="$("$root/tool/release/web_dist.sh")" || fail "no web dashboard"
cp -R "$web" "$work/build/bundle/web"

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

for path in /api/v1/health /health; do
  status="$(curl -sS --max-time 5 -o "$work/health.json" -w '%{http_code}' "$url$path")"
  [[ "$status" == "200" ]] || fail "GET $path answered $status"
  [[ "$(cat "$work/health.json")" == '{"status":"ok"}' ]] \
    || fail "GET $path body was: $(cat "$work/health.json")"
done

status="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$url/api/v1/events")"
[[ "$status" == "401" ]] || fail "GET /api/v1/events without a token answered $status, not 401"

status="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "$url/events")"
[[ "$status" == "404" ]] || fail "GET /events without Authorization answered $status, not 404"

token="$("$xpd" token create --name smoke --kind cli --data-dir "$data" 2>/dev/null)"
[[ "$token" =~ ^xpt_[A-Za-z0-9_-]{43}$ ]] || fail "xpd token create printed an unexpected token"
[[ -s "$data/xpath.db" ]] || fail "no database at $data/xpath.db"
if grep -qaF "$token" "$data"/xpath.db*; then
  fail "the token is stored in clear text"
fi

status="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $token" "$url/api/v1/events")"
[[ "$status" == "426" ]] \
  || fail "GET /api/v1/events with a fresh token answered $status, not 426"

for path in /api/v1/projects /projects; do
  name="$(echo "$path" | tr / _)"
  status="$(curl -sS --max-time 5 -D "$work/$name.headers" -o "$work/$name.json" \
    -w '%{http_code}' -H "Authorization: Bearer $token" "$url$path")"
  [[ "$status" == "200" ]] || fail "GET $path with the token answered $status"
done
cmp -s "$work/_api_v1_projects.json" "$work/_projects.json" \
  || fail "GET /projects and GET /api/v1/projects gave different bodies"
grep -qi '^deprecation: true' "$work/_projects.headers" \
  || fail "GET /projects did not say Deprecation: true"
if grep -qi '^deprecation:' "$work/_api_v1_projects.headers"; then
  fail "GET /api/v1/projects said it is deprecated"
fi

grep -q 'xpd serves the dashboard in ' "$work/server.log" \
  || fail "xpd did not find the dashboard in the bundle's web/"

# A browser asks for a page with `Accept: text/html`.
page() {
  curl -sS --max-time 5 -H 'Accept: text/html' -D "$work/page.headers" \
    -o "$work/page.html" -w '%{http_code}' "$url$1"
}
for path in / /runs/abc; do
  status="$(page "$path")"
  [[ "$status" == "200" ]] || fail "GET $path as a page answered $status"
  grep -q '<div id="app"></div>' "$work/page.html" || fail "GET $path is not the dashboard"
  grep -qi "^content-security-policy: default-src 'self'; script-src 'self';" "$work/page.headers" \
    || fail "GET $path has no Content-Security-Policy"
  grep -qi '^x-content-type-options: nosniff' "$work/page.headers" \
    || fail "GET $path does not say nosniff"
  grep -qi '^cache-control: no-cache' "$work/page.headers" || fail "GET $path may be cached"
done
asset="$(grep -Eo '/assets/[^"]+\.js' "$work/page.html" | head -1)"
[[ -n "$asset" ]] || fail "index.html names no script under /assets/"
status="$(curl -sS --max-time 5 -D "$work/asset.headers" -o /dev/null -w '%{http_code}' "$url$asset")"
[[ "$status" == "200" ]] || fail "GET $asset answered $status"
grep -qi '^cache-control: public, max-age=31536000, immutable' "$work/asset.headers" \
  || fail "GET $asset is not immutable"
grep -qi '^content-type: text/javascript' "$work/asset.headers" || fail "GET $asset is not JavaScript"
for path in /api/v2/projects /assets/missing.js; do
  status="$(page "$path")"
  [[ "$status" == "404" ]] || fail "GET $path as a page answered $status, not 404"
  grep -q '"error"' "$work/page.html" || fail "GET $path is not the JSON 404"
done

kill -TERM "$server_pid"
if wait "$server_pid"; then
  server_pid=""
else
  code=$?
  server_pid=""
  fail "xpd exited with $code after SIGTERM"
fi
grep -q 'shutting down' "$work/server.log" || fail "xpd did not log a graceful shutdown"

echo "OK: the xpd bundle answers /health, serves /api/v1 and its root aliases, guards /events, serves the web dashboard and shuts down cleanly."
