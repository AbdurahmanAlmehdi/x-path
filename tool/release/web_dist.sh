#!/usr/bin/env bash
# Prints the folder of the built web dashboard (apps/xp_web, ADR 0018) that
# the engine bundles carry as xpd/web:
#
#   - $XPATH_WEB_DIST when it is set: a dist/ built before (CI builds it once
#     and hands it on), or
#   - apps/xp_web/dist, after building it here with `npm ci && npm run build`
#     (needs Node 24 and npm on PATH). The build log goes to stderr only if
#     the build fails.
#
# Fails unless the folder holds an index.html.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() {
  echo "web_dist: $*" >&2
  exit 1
}

if [[ -n "${XPATH_WEB_DIST:-}" ]]; then
  web="$(cd "$XPATH_WEB_DIST" 2>/dev/null && pwd)" || die "XPATH_WEB_DIST ($XPATH_WEB_DIST) is not a folder"
else
  command -v npm >/dev/null 2>&1 \
    || die "building the web dashboard needs npm (Node 24), or set XPATH_WEB_DIST to a built dist/"
  log="$(mktemp)"
  trap 'rm -f "$log"' EXIT
  echo "Building the web dashboard..." >&2
  if ! (cd "$root/apps/xp_web" && npm ci --no-audit --no-fund && npm run build) >"$log" 2>&1; then
    cat "$log" >&2
    die "the web dashboard did not build"
  fi
  web="$root/apps/xp_web/dist"
fi
[[ -f "$web/index.html" ]] || die "no index.html in the web dashboard at $web"
echo "$web"
