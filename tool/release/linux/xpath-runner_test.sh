#!/usr/bin/env bash
# Tests tool/release/linux/xpath-runner, the entrypoint of the xpath-runner
# image, with a fake `xp` that records how it was run and exits with the code
# asked for:
#
#   tool/release/linux/xpath-runner_test.sh
#
# It checks that `runner start` is the default, that the xp a runner updated
# itself to (<data dir>/current/bin/xp) wins over the image's, that exit 75
# (switched version) is passed on so Docker restarts the runner, that 77, 73
# and 78 (revoked, replaced, not paired) become 0 with the reason so Docker
# does not, and that other commands keep their exit codes.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
entry="$root/tool/release/linux/xpath-runner"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "xpath-runner_test: $*" >&2
  [[ -f "$work/err.log" ]] && { echo "--- stderr ---" >&2; cat "$work/err.log" >&2; }
  exit 1
}

# A fake xp at $1 that appends "<name> <arguments>" to calls.log and exits
# with $FAKE_EXIT.
fake_xp() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<EOF
#!/bin/sh
echo "$2 \$*" >>"$work/calls.log"
exit "\${FAKE_EXIT:-0}"
EOF
  chmod +x "$1"
}
fake_xp "$work/image/xp" image

# Runs the entrypoint with a data directory of its own; sets $code.
data="$work/data"
run() {
  local exit_code="$1"
  shift
  rm -f "$work/calls.log"
  set +e
  env -i PATH=/usr/bin:/bin HOME="$data/home" XP_RUNNER_DATA_DIR="$data" \
    XPATH_RUNNER_XP="$work/image/xp" FAKE_EXIT="$exit_code" \
    sh "$entry" "$@" 2>"$work/err.log"
  code=$?
  set -e
}

echo "1. runner start by default, with the image's xp..."
run 0
[[ "$code" == 0 ]] || fail "exit $code"
grep -qx "image runner start" "$work/calls.log" || fail "ran $(cat "$work/calls.log")"
[[ -d "$data/home" ]] || fail "no home folder made"

echo "2. the xp the runner updated itself to wins..."
fake_xp "$data/current/bin/xp" current
run 0 runner doctor
grep -qx "current runner doctor" "$work/calls.log" || fail "ran $(cat "$work/calls.log")"
rm -rf "$data/current"

echo "3. a switched version (75) is passed on, so Docker restarts it..."
run 75 runner start
[[ "$code" == 75 ]] || fail "exit $code for 75"

echo "4. revoked, replaced and not paired stop Docker restarting it..."
for pair in "77:revoked" "73:took over" "78:not paired"; do
  run "${pair%%:*}" runner start
  [[ "$code" == 0 ]] || fail "exit $code for ${pair%%:*}"
  grep -q "${pair#*:}" "$work/err.log" || fail "no reason for ${pair%%:*}"
done

echo "5. other commands keep their exit codes..."
run 77 runner pair --engine https://e --token xpp_x
[[ "$code" == 77 ]] || fail "runner pair exit $code"
run 1 runner doctor
[[ "$code" == 1 ]] || fail "runner doctor exit $code"

echo "OK: the entrypoint runs the right xp and maps the exit codes for Docker."
